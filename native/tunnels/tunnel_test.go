package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/netip"
	"testing"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/ssh"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func wgKeys(t *testing.T) (priv, pub []byte) {
	priv = make([]byte, 32)
	rand.Read(priv)
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	pub, err := curve25519.X25519(priv, curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return priv, pub
}

// echo відповідає тим самим — замість справжнього RDP-сервера.
func echo(ln net.Listener) {
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go func() { defer c.Close(); io.Copy(c, c) }()
	}
}

func roundTrip(t *testing.T, d dialer, target string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	c, err := d.DialContext(ctx, "tcp", target)
	if err != nil {
		t.Fatalf("dial through tunnel: %v", err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := c.Write([]byte("mhrd")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "mhrd" {
		t.Fatalf("echo through tunnel: %q %v", buf, err)
	}
}

// Сервер WireGuard на loopback (теж netstack) з ехо-сервісом на 10.9.0.1:3389; клієнт —
// наш startWireGuard із конфігом, як після імпорту .conf.
func TestWireGuardThroughNetstack(t *testing.T) {
	sPriv, sPub := wgKeys(t)
	cPriv, cPub := wgKeys(t)

	sTun, sNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.9.0.1")}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	server := device.NewDevice(sTun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer server.Close()
	// Порт сервера — вільний UDP на loopback.
	probe, _ := net.ListenPacket("udp4", "127.0.0.1:0")
	port := probe.LocalAddr().(*net.UDPAddr).Port
	probe.Close()
	cfg := fmt.Sprintf("private_key=%x\nlisten_port=%d\npublic_key=%x\nallowed_ip=10.9.0.2/32\n", sPriv, port, cPub)
	if err := server.IpcSet(cfg); err != nil {
		t.Fatal(err)
	}
	server.Up()
	ln, err := sNet.ListenTCP(&net.TCPAddr{IP: net.ParseIP("10.9.0.1"), Port: 3389})
	if err != nil {
		t.Fatal(err)
	}
	go echo(ln)

	d, err := startWireGuard(&wireGuardConf{
		PrivateKey:    base64.StdEncoding.EncodeToString(cPriv),
		Addresses:     []string{"10.9.0.2/24"},
		MTU:           1420,
		PeerPublicKey: base64.StdEncoding.EncodeToString(sPub),
		Endpoint:      fmt.Sprintf("localhost:%d", port), // ім'я — перевіряємо й резолв
		AllowedIPs:    []string{"10.9.0.0/24"},
		Keepalive:     25,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close()
	roundTrip(t, d, "10.9.0.1:3389")
}

// SSH-сервер, що вміє лише переадресацію портів (direct-tcpip), як `ssh -L` на справжньому.
func startSSHServer(t *testing.T, password string) (addr string, hostKey ssh.PublicKey) {
	_, edPriv, _ := ed25519.GenerateKey(rand.Reader)
	signer, err := ssh.NewSignerFromKey(edPriv)
	if err != nil {
		t.Fatal(err)
	}
	cfg := &ssh.ServerConfig{
		PasswordCallback: func(_ ssh.ConnMetadata, p []byte) (*ssh.Permissions, error) {
			if string(p) == password {
				return nil, nil
			}
			return nil, fmt.Errorf("denied")
		},
	}
	cfg.AddHostKey(signer)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			nc, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				_, chans, reqs, err := ssh.NewServerConn(nc, cfg)
				if err != nil {
					return
				}
				go ssh.DiscardRequests(reqs)
				for nch := range chans {
					if nch.ChannelType() != "direct-tcpip" {
						nch.Reject(ssh.UnknownChannelType, "")
						continue
					}
					// RFC 4254 7.2: host, port, originator host, originator port
					extra := nch.ExtraData()
					hl := binary.BigEndian.Uint32(extra)
					host := string(extra[4 : 4+hl])
					port := binary.BigEndian.Uint32(extra[4+hl:])
					target, err := net.Dial("tcp", net.JoinHostPort(host, fmt.Sprint(port)))
					if err != nil {
						nch.Reject(ssh.ConnectionFailed, err.Error())
						continue
					}
					ch, rq, err := nch.Accept()
					if err != nil {
						target.Close()
						continue
					}
					go ssh.DiscardRequests(rq)
					go func() { io.Copy(ch, target); ch.CloseWrite() }()
					go func() { io.Copy(target, ch); target.Close() }()
				}
			}()
		}
	}()
	return ln.Addr().String(), signer.PublicKey()
}

func TestSSHForwardAndHostKey(t *testing.T) {
	echoLn, _ := net.Listen("tcp", "127.0.0.1:0")
	defer echoLn.Close()
	go echo(echoLn)
	addr, key := startSSHServer(t, "secret")
	host, portStr, _ := net.SplitHostPort(addr)
	var port int
	fmt.Sscan(portStr, &port)
	fp := ssh.FingerprintSHA256(key)

	// Ключ уже довірений — без питань.
	d, err := startSSH(&sshConf{Host: host, Port: port, Username: "me", Password: "secret", HostKeyPin: fp}, nil)
	if err != nil {
		t.Fatal(err)
	}
	roundTrip(t, d, echoLn.Addr().String())
	d.Close()

	// Інший відбиток — стоп, навіть із правильним паролем.
	_, err = startSSH(&sshConf{Host: host, Port: port, Username: "me", Password: "secret", HostKeyPin: "SHA256:other"}, nil)
	if te, ok := err.(*tunnelError); !ok || te.code != "hostKeyChanged" {
		t.Fatalf("want hostKeyChanged, got %v", err)
	}

	// Невірний пароль — auth.
	_, err = startSSH(&sshConf{Host: host, Port: port, Username: "me", Password: "nope", HostKeyPin: fp}, nil)
	if te, ok := err.(*tunnelError); !ok || te.code != "auth" {
		t.Fatalf("want auth, got %v", err)
	}

	// Невідомий ключ, користувач відмовився — hostKeyRejected.
	no := make(chan bool, 1)
	no <- false
	_, err = startSSH(&sshConf{Host: host, Port: port, Username: "me", Password: "secret"}, no)
	if te, ok := err.(*tunnelError); !ok || te.code != "hostKeyRejected" {
		t.Fatalf("want hostKeyRejected, got %v", err)
	}
}
