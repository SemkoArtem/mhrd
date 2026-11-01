package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/netip"
	"testing"
	"time"

	"golang.org/x/crypto/curve25519"
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

// Сервер WireGuard на loopback (теж netstack) з ехо-сервісом на 10.9.0.1:3389, що знає клієнта
// з ключем cPub. Повертає публічний ключ і UDP-порт сервера.
func wgServer(t *testing.T, cPub []byte) (sPub []byte, port int) {
	sPriv, sPub := wgKeys(t)

	sTun, sNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.9.0.1")}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	server := device.NewDevice(sTun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	t.Cleanup(server.Close)
	// Порт сервера — вільний UDP на loopback.
	probe, _ := net.ListenPacket("udp4", "127.0.0.1:0")
	port = probe.LocalAddr().(*net.UDPAddr).Port
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
	return sPub, port
}

func clientConf(cPriv, sPub []byte, port int) *wireGuardConf {
	return &wireGuardConf{
		PrivateKey:    base64.StdEncoding.EncodeToString(cPriv),
		Addresses:     []string{"10.9.0.2/24"},
		MTU:           1420,
		PeerPublicKey: base64.StdEncoding.EncodeToString(sPub),
		Endpoint:      fmt.Sprintf("localhost:%d", port), // ім'я — перевіряємо й резолв
		AllowedIPs:    []string{"10.9.0.0/24"},
		Keepalive:     25,
	}
}

// Клієнт — наш startWireGuard із конфігом, як після імпорту .conf.
func TestWireGuardThroughNetstack(t *testing.T) {
	cPriv, cPub := wgKeys(t)
	sPub, port := wgServer(t, cPub)
	d, err := startWireGuard(clientConf(cPriv, sPub, port))
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close()
	roundTrip(t, d, "10.9.0.1:3389")
	if _, err := dialTime(d, "10.9.0.1:3389"); err != nil { // замір затримки для плашки
		t.Fatalf("dialTime: %v", err)
	}
	if _, err := dialTime(d, "10.9.0.1:3390"); err == nil {
		t.Fatal("dialTime to a closed port should fail")
	}
}

// Перевірка стану: сервер, що знає клієнта, відповідає на рукостискання; чужий — ні.
func TestWireGuardHandshakeCheck(t *testing.T) {
	cPriv, cPub := wgKeys(t)
	sPub, port := wgServer(t, cPub)
	d, err := startWireGuard(clientConf(cPriv, sPub, port))
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close()
	if _, err := d.(*wgDialer).waitHandshake(10 * time.Second); err != nil {
		t.Fatalf("handshake: %v", err)
	}

	stranger, _ := wgKeys(t)
	d2, err := startWireGuard(clientConf(stranger, sPub, port))
	if err != nil {
		t.Fatal(err)
	}
	defer d2.Close()
	if _, err := d2.(*wgDialer).waitHandshake(2 * time.Second); err == nil {
		t.Fatal("handshake with unknown client key should fail")
	}
}
