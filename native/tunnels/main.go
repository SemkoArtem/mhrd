// mhrd-tunnel — вбудований тунель до одного ПК (SPEC → «Вбудовані тунелі», «Інші маршрути»).
//
// Застосунок запускає процес і пише в stdin рядки JSON (секрети — лише сюди, ніколи в аргументи):
//
//	{"type":"wireguard"|"ssh","target":"host:port", "wireguard":{...} | "ssh":{...}}
//	{"trustHostKey":true|false}   — відповідь на подію hostKey (SSH, ключ ще не довірений)
//	{"watchPid":1234}             — процес mhrd-session; коли він завершиться, тунель теж
//
// У stdout — рядки JSON-подій:
//
//	{"event":"hostKey","fingerprint":"SHA256:..."}
//	{"event":"listening","port":54321}   — можна підключатися до 127.0.0.1:port
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
	SSH       *sshConf        `json:"ssh"`
	Trust     *bool           `json:"trustHostKey"`
	WatchPid  int             `json:"watchPid"`
}

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

	// Подальші повідомлення: відповідь про ключ SSH і PID сеансу.
	trust := make(chan bool, 1)
	watch := make(chan int, 1)
	go func() {
		for in.Scan() {
			var m request
			if json.Unmarshal(in.Bytes(), &m) != nil {
				continue
			}
			if m.Trust != nil {
				trust <- *m.Trust
			}
			if m.WatchPid > 0 {
				watch <- m.WatchPid
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
		d, err = startWireGuard(req.WireGuard)
	case "ssh":
		if req.SSH == nil {
			fail("config", fmt.Errorf("no ssh section"))
		}
		d, err = startSSH(req.SSH, trust)
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

	// Перевіряємо, що ПК справді досяжний через тунель, — інакше користувач бачив би
	// загадкову помилку RDP замість зрозумілої «тунель є, а ПК не відповідає».
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	probe, err := d.DialContext(ctx, "tcp", req.Target)
	cancel()
	if err != nil {
		fail("unreachable", err)
	}
	probe.Close()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fail("listen", err)
	}
	go serve(ln, d, req.Target)
	emit(map[string]any{"event": "listening", "port": ln.Addr().(*net.TCPAddr).Port})

	// Живемо, поки живий сеанс: FreeRDP при перепідключенні знову прийде на цей самий порт.
	pid, ok := <-watch
	if !ok {
		return
	}
	waitProcess(pid)
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
