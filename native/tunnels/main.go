// mhrd-tunnel — вбудований тунель (SPEC → «Вбудовані тунелі»): один процес на ключ WireGuard
// для всіх сеансів, що через нього йдуть.
//
// Застосунок запускає процес і пише в stdin рядки JSON (секрети — лише сюди, ніколи в аргументи):
//
//	{"type":"wireguard","target":"host:port","wireguard":{...},"stateFile":"...","token":"..."}
//	{"watchPid":1234,"lid":1}       — процес mhrd-session, що ходить через локальний порт lid; тунель
//	                                  живе, поки живий хоч один такий, а порт lid закривається разом
//	                                  зі своїм сеансом
//	{"forward":"host:port","id":2}  — ще один ПК крізь цей самий тунель (наступний сеанс із тим самим
//	                                  ключем): один процес на ключ, інакше кілька процесів з одним
//	                                  ключем WireGuard перебивали б один одному з'єднання з сервером
//	{"ping":true,"target":"host:port","id":3} — затримка до ПК крізь тунель (відповідь — pong з тим
//	                                  самим id; без target — до першого ПК)
//
// stateFile/token: працюючий тунель записує у stateFile {"pid","port","token"} — порт керування на
// 127.0.0.1. Інша чи перезапущена копія MHRD (вікна сеансів живуть і без головного вікна) під'єднується
// туди, першим рядком надсилає {"token":"..."} і далі говорить тими самими рядками, що й stdin, —
// замість рукостискання з тим самим ключем, яке перебило б сеанси. Файл — лише для цього
// користувача; без токена порт керування нічого не приймає.
//
// Або перевірка, чи тунель живий: {"type":"wireguard","check":true,"wireguard":{...}}; з "target" —
// ще й чи відповідає ПК крізь тунель.
//
// У stdout (і всім під'єднаним через порт керування) — рядки JSON-подій:
//
//	{"event":"listening","port":54321,"lid":1[,"id":2]} — можна підключатися до 127.0.0.1:port
//	{"event":"forwardError","id":2,"code":"unreachable","detail":"..."} — ПК крізь тунель не відповів
//	{"event":"ok","handshakeMs":120,"targetMs":35} — відповідь на перевірку
//	{"event":"pong","ms":35,"id":3} / {"event":"pong","error":"...","id":3}
//	{"event":"error","code":"...","detail":"..."}
//
// WireGuard працює в програмному мережевому стеку (wireguard-go netstack): без драйвера, без
// прав адміністратора і не чіпає системних маршрутів та інших VPN.
package main

import (
	"bufio"
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

type request struct {
	Type      string         `json:"type"`
	Target    string         `json:"target"`
	WireGuard *wireGuardConf `json:"wireguard"`
	WatchPid  int            `json:"watchPid"`
	Lid       int            `json:"lid"`
	Check     bool           `json:"check"`
	Ping      bool           `json:"ping"`
	Forward   string         `json:"forward"`
	ID        int            `json:"id"`
	StateFile string         `json:"stateFile"`
	Token     string         `json:"token"`
}

// Скільки чекати рукостискання під час перевірки (wireguard-go повторює спробу кожні 5 с).
var handshakeTimeout = 15 * time.Second

// Скільки тунель чекає після кінця останнього сеансу, перш ніж вийти: застосунок міг саме
// попросити ще один ПК крізь нього (forward), а процес сеансу ще не встиг запуститися.
var idleGrace = 30 * time.Second

// dialer — те, що вміє тунель: відкрити TCP-з'єднання до цілі зсередини.
type dialer interface {
	DialContext(ctx context.Context, network, address string) (net.Conn, error)
	Close() error
}

var (
	outMu    sync.Mutex
	controls = map[net.Conn]bool{} // під'єднані через порт керування (outMu)
)

func emit(v map[string]any) {
	b, _ := json.Marshal(v)
	line := append(b, '\n')
	outMu.Lock()
	defer outMu.Unlock()
	os.Stdout.Write(line)
	for c := range controls {
		c.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if _, err := c.Write(line); err != nil {
			c.Close()
			delete(controls, c)
		}
	}
}

func fail(code string, err error) {
	detail := ""
	if err != nil {
		detail = err.Error()
	}
	emit(map[string]any{"event": "error", "code": code, "detail": detail})
	os.Exit(1)
}

// Повідомлення застосунку (зі stdin чи порту керування) — у свої черги.
type inbox struct {
	pids     chan request
	forwards chan request
	pings    chan request
}

func (b *inbox) handle(line []byte) {
	var m request
	if json.Unmarshal(line, &m) != nil {
		return
	}
	if m.WatchPid > 0 {
		b.pids <- m
	}
	if m.Forward != "" {
		b.forwards <- m
	}
	if m.Ping {
		select {
		case b.pings <- m:
		default: // попередні заміри ще не відповіли — цей пропускаємо
		}
	}
}

func main() {
	// Лише для тестів: коротше очікування наступного сеансу.
	if ms, err := strconv.Atoi(os.Getenv("MHRD_TUNNEL_IDLE_MS")); err == nil && ms > 0 {
		idleGrace = time.Duration(ms) * time.Millisecond
	}
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
	box := &inbox{pids: make(chan request, 16), forwards: make(chan request, 16), pings: make(chan request, 8)}
	stdinClosed := make(chan struct{})
	go func() {
		for in.Scan() {
			box.handle(in.Bytes())
		}
		close(stdinClosed) // застосунок закрився — далі хіба через порт керування
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

	// Локальні порти до ПК; кожен закривається, коли закінчився його сеанс (watchPid з lid).
	var lmu sync.Mutex
	listeners := map[int]net.Listener{}
	nextLid := 0
	listen := func(target string) (int, int, error) {
		l, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return 0, 0, err
		}
		lmu.Lock()
		nextLid++
		lid := nextLid
		listeners[lid] = l
		lmu.Unlock()
		go serve(l, d, target)
		return l.Addr().(*net.TCPAddr).Port, lid, nil
	}
	closeLid := func(lid int) {
		lmu.Lock()
		if l := listeners[lid]; l != nil {
			l.Close()
			delete(listeners, lid)
		}
		lmu.Unlock()
	}

	port, lid, err := listen(req.Target)
	if err != nil {
		fail("listen", err)
	}

	// Порт керування для інших копій MHRD (див. stateFile вище).
	if req.StateFile != "" && req.Token != "" {
		if err := serveControl(req.StateFile, req.Token, box); err == nil {
			defer removeState(req.StateFile)
		}
	}
	emit(map[string]any{"event": "listening", "port": port, "lid": lid})

	var mu sync.Mutex
	lastActivity := time.Now()
	touch := func() {
		mu.Lock()
		lastActivity = time.Now()
		mu.Unlock()
	}
	// Кожен запит — окремо: ПК, що не відповідає (до 20 с), не затримує решту сеансів тунелю.
	go func() {
		for f := range box.forwards {
			touch()
			go func(f request) {
				if _, err := dialTime(d, f.Forward); err != nil {
					emit(map[string]any{"event": "forwardError", "id": f.ID, "code": "unreachable", "detail": err.Error()})
					return
				}
				port, lid, err := listen(f.Forward)
				if err != nil {
					emit(map[string]any{"event": "forwardError", "id": f.ID, "code": "listen", "detail": err.Error()})
					return
				}
				emit(map[string]any{"event": "listening", "id": f.ID, "port": port, "lid": lid})
			}(f)
		}
	}()

	// Затримка до ПК крізь тунель — для плашки сеансу (target — до якого ПК; id — чия це відповідь).
	// Теж кожен окремо (до 8 одночасно — стільки вміщує черга pings).
	busy := make(chan struct{}, 8)
	go func() {
		for p := range box.pings {
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
	ended := make(chan int, 16)
	active, sawPid := 0, false
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	closed := stdinClosed
	for {
		select {
		case w := <-box.pids:
			active++
			sawPid = true
			touch()
			go func() {
				waitProcess(w.WatchPid)
				ended <- w.Lid
			}()
		case lid := <-ended:
			active--
			touch()
			if lid > 0 {
				closeLid(lid) // сеанс закінчився — його порт більше нікому не потрібен
			}
		case <-closed:
			closed = nil // більше не спрацює
			if !sawPid {
				return // застосунок пішов, так і не запустивши сеансу
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

// serveControl відкриває порт керування на 127.0.0.1 і записує stateFile {"pid","port","token"}
// (тека й файл — лише для цього користувача). Під'єднаний має першим рядком надіслати токен.
func serveControl(stateFile, token string, box *inbox) error {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				sc := bufio.NewScanner(c)
				sc.Buffer(make([]byte, 64*1024), 1<<20)
				c.SetReadDeadline(time.Now().Add(5 * time.Second))
				var hello struct {
					Token string `json:"token"`
				}
				if !sc.Scan() || json.Unmarshal(sc.Bytes(), &hello) != nil ||
					subtle.ConstantTimeCompare([]byte(hello.Token), []byte(token)) != 1 {
					c.Close()
					return
				}
				c.SetReadDeadline(time.Time{})
				outMu.Lock()
				controls[c] = true
				c.Write([]byte("{\"event\":\"hello\"}\n")) // токен прийнято — застосунок чекає саме цього
				outMu.Unlock()
				for sc.Scan() {
					box.handle(sc.Bytes())
				}
				outMu.Lock()
				delete(controls, c)
				outMu.Unlock()
				c.Close()
			}()
		}
	}()
	b, _ := json.Marshal(map[string]any{"pid": os.Getpid(), "port": l.Addr().(*net.TCPAddr).Port, "token": token})
	if err := os.MkdirAll(filepath.Dir(stateFile), 0o700); err != nil {
		l.Close()
		return err
	}
	if err := privateDir(filepath.Dir(stateFile)); err != nil {
		l.Close() // без «візитки»: краще друга копія MHRD не знайде тунель, ніж токен побачить чужий
		return err
	}
	tmp := fmt.Sprintf("%s.%d.tmp", stateFile, os.Getpid())
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		l.Close()
		return err
	}
	if err := os.Rename(tmp, stateFile); err != nil {
		os.Remove(tmp)
		l.Close()
		return err
	}
	return nil
}

// removeState прибирає stateFile, якщо він ще наш (інший процес міг записати свій).
func removeState(stateFile string) {
	b, err := os.ReadFile(stateFile)
	if err != nil {
		return
	}
	var s struct {
		Pid int `json:"pid"`
	}
	if json.Unmarshal(b, &s) == nil && s.Pid == os.Getpid() {
		os.Remove(stateFile)
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
