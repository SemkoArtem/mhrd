package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"os/exec"
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
	took, err := d.(*wgDialer).waitHandshake(10 * time.Second)
	if err != nil {
		t.Fatalf("handshake: %v", err)
	}
	// На loopback рукостискання — мілісекунди; раніше крок опитування давав рівно 100 мс.
	if took <= 0 || took >= 100*time.Millisecond {
		t.Fatalf("handshake took %v, want a real loopback time (< 100 ms)", took)
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

// Процес mhrd-tunnel у тесті — цей самий тестовий бінарник з MHRD_TUNNEL_MAIN=1.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("MHRD_TUNNEL_MAIN") != "1" {
		t.Skip("лише як процес тунелю для TestSharedTunnelProcess")
	}
	main()
	os.Exit(0)
}

// Один процес на профіль: перший ПК — з першого запиту, ще один — forward з id; заміри затримки
// відповідають тим самим id; stdin закрито й сеансів немає — процес виходить.
func TestSharedTunnelProcess(t *testing.T) {
	cPriv, cPub := wgKeys(t)
	sPub, port := wgServer(t, cPub)

	cmd := exec.Command(os.Args[0], "-test.run=^TestHelperProcess$")
	cmd.Env = append(os.Environ(), "MHRD_TUNNEL_MAIN=1")
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer cmd.Process.Kill()
	events := bufio.NewScanner(stdout)
	next := func() map[string]any {
		t.Helper()
		if !events.Scan() {
			t.Fatalf("tunnel exited: %v", events.Err())
		}
		var m map[string]any
		if err := json.Unmarshal(events.Bytes(), &m); err != nil {
			t.Fatalf("bad event %q", events.Text())
		}
		return m
	}
	send := func(v any) {
		b, _ := json.Marshal(v)
		stdin.Write(append(b, '\n'))
	}
	echoVia := func(port int) {
		t.Helper()
		c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 10*time.Second)
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(10 * time.Second))
		c.Write([]byte("mhrd"))
		buf := make([]byte, 4)
		if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "mhrd" {
			t.Fatalf("echo via tunnel port %d: %q %v", port, buf, err)
		}
	}

	send(map[string]any{"type": "wireguard", "target": "10.9.0.1:3389", "wireguard": clientConf(cPriv, sPub, port)})
	first := next()
	if first["event"] != "listening" {
		t.Fatalf("first: %v", first)
	}
	echoVia(int(first["port"].(float64)))

	send(map[string]any{"forward": "10.9.0.1:3389", "id": 7})
	second := next()
	if second["event"] != "listening" || second["id"] != float64(7) || second["port"] == first["port"] {
		t.Fatalf("forward: %v", second)
	}
	echoVia(int(second["port"].(float64)))

	send(map[string]any{"forward": "10.9.0.1:3390", "id": 8}) // там нічого не слухає
	if e := next(); e["event"] != "forwardError" || e["id"] != float64(8) {
		t.Fatalf("forward to closed port: %v", e)
	}

	send(map[string]any{"ping": true, "id": 9, "target": "10.9.0.1:3389"})
	if e := next(); e["event"] != "pong" || e["id"] != float64(9) || e["ms"] == nil {
		t.Fatalf("ping: %v", e)
	}

	stdin.Close() // застосунок закрився, сеансів немає — тунель виходить сам
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("tunnel did not exit after stdin closed")
	}
}
