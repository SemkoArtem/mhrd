// mhrd-tunnel — вбудований тунель до одного ПК (SPEC → «Вбудовані тунелі»).
//
// Застосунок запускає процес і пише в stdin рядки JSON (секрети — лише сюди, ніколи в аргументи):
//
//	{"type":"wireguard","target":"host:port","wireguard":{...}}
//	{"watchPid":1234}             — процес mhrd-session; коли він завершиться, тунель теж
//
//	{"ping":true}                 — заміряти затримку до ПК крізь тунель (відповідь — pong)
//
// Або перевірка, чи тунель живий: {"type":"wireguard","check":true,"wireguard":{...}}; з "target" —
// ще й чи відповідає ПК крізь тунель.
//
// У stdout — рядки JSON-подій:
//
//	{"event":"listening","port":54321}   — можна підключатися до 127.0.0.1:port
//	{"event":"ok","handshakeMs":120,"targetMs":35} — відповідь на перевірку
//	{"event":"pong","ms":35} / {"event":"pong","error":"..."}
//	{"event":"error","code":"...","detail":"..."}
//
// WireGuard працює в програмному мережевому стеку (wireguard-go netstack): без драйвера, без
// прав адміністратора і не чіпає системних маршрутів та інших VPN.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"
)

type request struct {
	Type      string          `json:"type"`
	Target    string          `json:"target"`
	WireGuard *wireGuardConf  `json:"wireguard"`
	WatchPid  int             `json:"watchPid"`
	Check     bool            `json:"check"`
	Ping      bool            `json:"ping"`
}

// Скільки чекати рукостискання під час перевірки (wireguard-go повторює спробу кожні 5 с).
var handshakeTimeout = 15 * time.Second

// dialer — те, що вміє тунель: відкрити TCP-з'єднання до цілі зсередини.
type dialer interface {
	DialContext(ctx context.Context, network, address string) (net.Conn, error)
	Close() error
}

var outMu sync.Mutex

func emit(v map[string]any) {
	b, _ := json.Marshal(v)
	outMu.Lock()
	defer outMu.Unlock()
	os.Stdout.Write(append(b, '\n'))
}

func fail(code string, err error) {
	detail := ""
	if err != nil {
		detail = err.Error()
	}
	emit(map[string]any{"event": "error", "code": code, "detail": detail})
	os.Exit(1)
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 64*1024), 1<<20)
	if !in.Scan() {
		os.Exit(0) // застосунок закрився, так нічого й не попросивши
	}
	var req request
	if err := json.Unmarshal(in.Bytes(), &req); err != nil {
		fail("config", err)
	}

	// Подальші повідомлення: PID сеансу і заміри затримки.
	watch := make(chan int, 1)
	pings := make(chan struct{}, 4)
	go func() {
		for in.Scan() {
			var m request
			if json.Unmarshal(in.Bytes(), &m) != nil {
				continue
			}
			if m.WatchPid > 0 {
				watch <- m.WatchPid
			}
			if m.Ping {
				select {
				case pings <- struct{}{}:
				default: // попередні заміри ще не відповіли — цей пропускаємо
				}
			}
		}
		close(watch) // stdin закрито: якщо PID ще не прийшов — застосунок пішов, тунель не потрібен
	}()

	var d dialer
	var err error
	switch req.Type {
	case "wireguard":
		if req.WireGuard == nil {
			fail("config", fmt.Errorf("no wireguard section"))
		}
		if req.Check && req.WireGuard.Keepalive <= 0 {
			req.WireGuard.Keepalive = 25 // keepalive при Up одразу запускає рукостискання
		}
		d, err = startWireGuard(req.WireGuard)
	default:
		fail("config", fmt.Errorf("unknown type %q", req.Type))
	}
	if err != nil {
		if te, ok := err.(*tunnelError); ok {
			fail(te.code, te.err)
		}
		fail("connect", err)
	}
	defer d.Close()

	if req.Check {
		took, err := d.(*wgDialer).waitHandshake(handshakeTimeout)
		if err != nil {
			d.Close()
			fail("handshake", err)
		}
		ok := map[string]any{"event": "ok", "handshakeMs": took.Milliseconds()}
		if req.Target != "" { // перевірка ПК через тунель: ще й чи відповідає сам ПК
			ms, err := dialTime(d, req.Target)
			if err != nil {
				d.Close()
				fail("unreachable", err)
			}
			ok["targetMs"] = ms
		}
		emit(ok)
		return
	}

	// Перевіряємо, що ПК справді досяжний через тунель, — інакше користувач бачив би
	// загадкову помилку RDP замість зрозумілої «тунель є, а ПК не відповідає».
	if _, err := dialTime(d, req.Target); err != nil {
		fail("unreachable", err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fail("listen", err)
	}
	go serve(ln, d, req.Target)
	emit(map[string]any{"event": "listening", "port": ln.Addr().(*net.TCPAddr).Port})

	// Затримка до ПК через увесь тунель — для плашки сеансу.
	go func() {
		for range pings {
			if ms, err := dialTime(d, req.Target); err != nil {
				emit(map[string]any{"event": "pong", "error": err.Error()})
			} else {
				emit(map[string]any{"event": "pong", "ms": ms})
			}
		}
	}()

	// Живемо, поки живий сеанс: FreeRDP при перепідключенні знову прийде на цей самий порт.
	pid, ok := <-watch
	if !ok {
		return
	}
	waitProcess(pid)
}

// dialTime — скільки мс триває TCP-з'єднання з ціллю крізь тунель (≈ затримка в обидва боки).
func dialTime(d dialer, target string) (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	start := time.Now()
	c, err := d.DialContext(ctx, "tcp", target)
	if err != nil {
		return 0, err
	}
	ms := time.Since(start).Milliseconds()
	c.Close()
	return ms, nil
}

func serve(ln net.Listener, d dialer, target string) {
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go func() {
			defer c.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			r, err := d.DialContext(ctx, "tcp", target)
			cancel()
			if err != nil {
				return
			}
			defer r.Close()
			pipe(c, r)
		}()
	}
}

// pipe копіює дані в обидва боки, поки одна зі сторін не закриється.
func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
}

type tunnelError struct {
	code string
	err  error
}

func (e *tunnelError) Error() string { return e.code + ": " + e.err.Error() }
