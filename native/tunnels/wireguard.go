package main

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

// Поля — як у lib/util/wireguard_conf.dart (несекретні) + privateKey/presharedKey зі сховища.
type wireGuardConf struct {
	PrivateKey    string   `json:"privateKey"`
	PresharedKey  string   `json:"presharedKey"`
	Addresses     []string `json:"addresses"`
	DNS           []string `json:"dns"`
	MTU           int      `json:"mtu"`
	PeerPublicKey string   `json:"peerPublicKey"`
	Endpoint      string   `json:"endpoint"`
	AllowedIPs    []string `json:"allowedIps"`
	Keepalive     int      `json:"keepalive"`
}

type wgDialer struct {
	net *netstack.Net
	dev *device.Device
	up  time.Time // коли піднято пристрій — з цієї миті йде перше рукостискання
}

func (d *wgDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	return d.net.DialContext(ctx, network, address)
}

func (d *wgDialer) Close() error {
	d.dev.Close()
	return nil
}

// waitHandshake чекає першого рукостискання з сервером — перевірка, що тунель живий (сам по собі
// WireGuard мовчить, доки нема трафіку; рукостискання запускає keepalive при Up). Повертає, скільки
// воно тривало: за часом, який записав сам WireGuard (last_handshake_time), а не за кроком
// опитування — інакше будь-який швидкий сервер показував би рівно крок (100 мс).
func (d *wgDialer) waitHandshake(timeout time.Duration) (time.Duration, error) {
	start := d.up // рукостискання почалось, щойно пристрій піднято
	if start.IsZero() {
		start = time.Now()
	}
	for time.Since(start) < timeout {
		cfg, err := d.dev.IpcGet()
		if err != nil {
			return 0, err
		}
		var sec, nsec int64
		for _, line := range strings.Split(cfg, "\n") {
			if v, ok := strings.CutPrefix(line, "last_handshake_time_sec="); ok {
				sec, _ = strconv.ParseInt(v, 10, 64)
			} else if v, ok := strings.CutPrefix(line, "last_handshake_time_nsec="); ok {
				nsec, _ = strconv.ParseInt(v, 10, 64)
			}
		}
		if sec != 0 {
			took := time.Unix(sec, nsec).Sub(start)
			if took <= 0 || took > time.Since(start) {
				took = time.Since(start) // годинник стрибнув — хоча б приблизно
			}
			return took, nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	return 0, fmt.Errorf("no handshake in %s", timeout)
}

// Ключ WireGuard: base64 у .conf, hex — у налаштуваннях wireguard-go (UAPI).
func keyHex(b64 string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil || len(raw) != 32 {
		return "", fmt.Errorf("bad key")
	}
	return hex.EncodeToString(raw), nil
}

func startWireGuard(c *wireGuardConf) (dialer, error) {
	bad := func(err error) error { return &tunnelError{"config", err} }

	var addrs []netip.Addr
	for _, a := range c.Addresses {
		if p, err := netip.ParsePrefix(a); err == nil {
			addrs = append(addrs, p.Addr())
		} else if ip, err := netip.ParseAddr(a); err == nil {
			addrs = append(addrs, ip)
		} else {
			return nil, bad(fmt.Errorf("address %q", a))
		}
	}
	if len(addrs) == 0 {
		return nil, bad(fmt.Errorf("no address"))
	}
	var dns []netip.Addr
	for _, s := range c.DNS {
		if ip, err := netip.ParseAddr(s); err == nil {
			dns = append(dns, ip) // пошукові домени в DNS= пропускаємо
		}
	}
	mtu := c.MTU
	if mtu <= 0 {
		mtu = 1420
	}

	priv, err := keyHex(c.PrivateKey)
	if err != nil {
		return nil, bad(fmt.Errorf("private key"))
	}
	pub, err := keyHex(c.PeerPublicKey)
	if err != nil {
		return nil, bad(fmt.Errorf("peer public key"))
	}

	// UAPI приймає лише IP:порт — ім'я сервера резолвимо самі.
	host, portStr, err := net.SplitHostPort(c.Endpoint)
	if err != nil {
		return nil, bad(fmt.Errorf("endpoint %q", c.Endpoint))
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port <= 0 || port > 65535 {
		return nil, bad(fmt.Errorf("endpoint port %q", portStr))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	cancel()
	if err != nil || len(ips) == 0 {
		return nil, &tunnelError{"endpointDns", fmt.Errorf("%s: %v", host, err)}
	}
	ep := ips[0]
	for _, ip := range ips {
		if ip.Is4() { // IPv4 надійніший у більшості мереж
			ep = ip
			break
		}
	}

	var uapi strings.Builder
	fmt.Fprintf(&uapi, "private_key=%s\n", priv)
	fmt.Fprintf(&uapi, "public_key=%s\n", pub)
	if c.PresharedKey != "" {
		psk, err := keyHex(c.PresharedKey)
		if err != nil {
			return nil, bad(fmt.Errorf("preshared key"))
		}
		fmt.Fprintf(&uapi, "preshared_key=%s\n", psk)
	}
	fmt.Fprintf(&uapi, "endpoint=%s\n", netip.AddrPortFrom(ep.Unmap(), uint16(port)))
	if c.Keepalive > 0 {
		fmt.Fprintf(&uapi, "persistent_keepalive_interval=%d\n", c.Keepalive)
	}
	allowed := c.AllowedIPs
	if len(allowed) == 0 {
		allowed = []string{"0.0.0.0/0", "::/0"}
	}
	for _, a := range allowed {
		fmt.Fprintf(&uapi, "allowed_ip=%s\n", a)
	}

	tunDev, tnet, err := netstack.CreateNetTUN(addrs, dns, mtu)
	if err != nil {
		return nil, &tunnelError{"start", err}
	}
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	if err := dev.IpcSet(uapi.String()); err != nil {
		dev.Close()
		return nil, bad(err)
	}
	up := time.Now()
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, &tunnelError{"start", err}
	}
	return &wgDialer{net: tnet, dev: dev, up: up}, nil
}
