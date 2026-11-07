// mhrd-tunnel — вбудований тунель до одного ПК (SPEC → «Вбудовані тунелі»).
//
// Застосунок запускає процес і пише в stdin рядки JSON (секрети — лише сюди, ніколи в аргументи):
//
//	{"type":"wireguard","target":"host:port","wireguard":{...}}
//	{"watchPid":1234}             — процес mhrd-session; тунель живе, поки живий хоч один такий
//	{"forward":"host:port","id":2} — ще один ПК крізь цей самий тунель (наступний сеанс із тим самим
//	                                профілем): один процес на профіль, інакше кілька процесів з одним
//	                                ключем WireGuard перебивали б один одному з'єднання з сервером
//
//	{"ping":true,"target":"host:port","id":3} — затримка до ПК крізь тунель (відповідь — pong з тим
//	                                самим id; без target — до першого ПК)
//
// Або перевірка, чи тунель живий: {"type":"wireguard","check":true,"wireguard":{...}}; з "target" —
// ще й чи відповідає ПК крізь тунель.
//
// У stdout — рядки JSON-подій:
//
//	{"event":"listening","port":54321[,"id":2]} — можна підключатися до 127.0.0.1:port
//	{"event":"forwardError","id":2,"code":"unreachable","detail":"..."} — ПК крізь тунель не відповів
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
	Type      string         `json:"type"`
	Target    string         `json:"target"`
	WireGuard *wireGuardConf `json:"wireguard"`
	WatchPid  int            `json:"watchPid"`
	Check     bool           `json:"check"`
	Ping      bool           `json:"ping"`
	Forward   string         `json:"forward"`
	ID        int            `json:"id"`
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

// Скільки тунель чекає після кінця останнього сеансу, перш ніж вийти: застосунок міг саме
// попросити ще один ПК крізь нього (forward), а процес сеансу ще не встиг запуститися.
var idleGrace = 30 * time.Second

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

	// Подальші повідомлення: PID сеансів, ще ПК крізь той самий тунель, заміри затримки.
	pids := make(chan int, 16)
	forwards := make(chan request, 16)
	pings := make(chan request, 8)
	stdinClosed := make(chan struct{})
	go func() {
		for in.Scan() {
			var m request
			if json.Unmarshal(in.Bytes(), &m) != nil {
				continue
			}
			if m.WatchPid > 0 {
				pids <- m.WatchPid
			}
			if m.Forward != "" {
				forwards <- m
			}
			if m.Ping {
				select {
				case pings <- m:
				default: // попередні заміри ще не відповіли — цей пропускаємо
				}
			}
		}
		close(stdinClosed) // застосунок закрився — нових сеансів не буде
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

	// Ще ПК крізь цей самий тунель (наступні сеанси з тим самим профілем): один процес на профіль —
	// інакше кілька процесів з одним ключем WireGuard перебивали б один одному з'єднання з сервером.
	var mu sync.Mutex
	lastActivity := time.Now()
	touch := func() {
		mu.Lock()
		lastActivity = time.Now()
		mu.Unlock()
	}
	// Кожен запит — окремо: ПК, що не відповідає (до 20 с), не затримує решту сеансів тунелю.
	go func() {
		for f := range forwards {
			touch()
			go func(f request) {
				if _, err := dialTime(d, f.Forward); err != nil {
					emit(map[string]any{"event": "forwardError", "id": f.ID, "code": "unreachable", "detail": err.Error()})
					return
				}
				l, err := net.Listen("tcp", "127.0.0.1:0")
				if err != nil {
					emit(map[string]any{"event": "forwardError", "id": f.ID, "code": "listen", "detail": err.Error()})
					return
				}
				go serve(l, d, f.Forward)
				emit(map[string]any{"event": "listening", "id": f.ID, "port": l.Addr().(*net.TCPAddr).Port})
			}(f)
		}
	}()

	// Затримка до ПК крізь тунель — для плашки сеансу (target — до якого ПК; id — чия це відповідь).
	// Теж кожен окремо (до 8 одночасно — стільки вміщує черга pings).
	busy := make(chan struct{}, 8)
	go func() {
		for p := range pings {
			busy <- struct{}{}
			go func(p request) {
				defer func() { <-busy }()
				target := p.Target
				if target == "" {
					target = req.Target
				}
				ev := map[string]any{"event": "pong"}
				if p.ID != 0 {
					ev["id"] = p.ID
				}
				if ms, err := dialTime(d, target); err != nil {
					ev["error"] = err.Error()
				} else {
					ev["ms"] = ms
				}
				emit(ev)
			}(p)
		}
	}()

	// Живемо, поки живий хоч один сеанс: FreeRDP при перепідключенні знову прийде на свій порт.
	ended := make(chan struct{}, 16)
	active, sawPid := 0, false
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	closed := stdinClosed
	for {
		select {
		case pid := <-pids:
			active++
			sawPid = true
			touch()
			go func() {
				waitProcess(pid)
				ended <- struct{}{}
			}()
		case <-ended:
			active--
			touch()
		case <-closed:
			closed = nil // більше не спрацює
			if active == 0 {
				return // застосунок пішов, сеансів крізь тунель немає
			}
		case <-tick.C:
			mu.Lock()
			idle := time.Since(lastActivity)
			mu.Unlock()
			if active == 0 && (sawPid || closed == nil) && idle > idleGrace {
				return
			}
		}
	}
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
