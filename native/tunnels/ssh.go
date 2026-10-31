package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// SSH-тунель: як `ssh -L`, але всередині MHRD. Секрет — пароль або приватний ключ (текст),
// приходить лише через stdin.
type sshConf struct {
	Host       string `json:"host"`
	Port       int    `json:"port"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	PrivateKey string `json:"privateKey"`
	Passphrase string `json:"passphrase"`
	HostKeyPin string `json:"hostKeyPin"` // SHA256:… — ключ, якому вже довіряють
}

type sshDialer struct{ client *ssh.Client }

func (d *sshDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	return d.client.DialContext(ctx, network, address)
}

func (d *sshDialer) Close() error { return d.client.Close() }

func startSSH(c *sshConf, trust <-chan bool) (dialer, error) {
	var auth []ssh.AuthMethod
	if strings.TrimSpace(c.PrivateKey) != "" {
		var signer ssh.Signer
		var err error
		if c.Passphrase != "" {
			signer, err = ssh.ParsePrivateKeyWithPassphrase([]byte(c.PrivateKey), []byte(c.Passphrase))
		} else {
			signer, err = ssh.ParsePrivateKey([]byte(c.PrivateKey))
		}
		var missing *ssh.PassphraseMissingError
		if errors.As(err, &missing) {
			return nil, &tunnelError{"keyPassphrase", err}
		}
		if err != nil {
			return nil, &tunnelError{"badKey", err}
		}
		auth = append(auth, ssh.PublicKeys(signer))
	}
	if c.Password != "" {
		auth = append(auth, ssh.Password(c.Password))
	}
	if len(auth) == 0 {
		return nil, &tunnelError{"auth", fmt.Errorf("no password or key")}
	}

	// Ключ сервера: збігається з довіреним — далі; інший — стоп (можлива підміна);
	// невідомий — питаємо застосунок, як із сертифікатом RDP.
	var hostKeyErr *tunnelError
	check := func(_ string, _ net.Addr, key ssh.PublicKey) error {
		fp := ssh.FingerprintSHA256(key)
		if c.HostKeyPin != "" {
			if fp == c.HostKeyPin {
				return nil
			}
			hostKeyErr = &tunnelError{"hostKeyChanged", fmt.Errorf("%s", fp)}
			return hostKeyErr
		}
		emit(map[string]any{"event": "hostKey", "fingerprint": fp})
		select {
		case ok := <-trust:
			if ok {
				return nil
			}
		case <-time.After(5 * time.Minute):
		}
		hostKeyErr = &tunnelError{"hostKeyRejected", fmt.Errorf("%s", fp)}
		return hostKeyErr
	}

	port := c.Port
	if port == 0 {
		port = 22
	}
	cfg := &ssh.ClientConfig{
		User:            c.Username,
		Auth:            auth,
		HostKeyCallback: check,
		Timeout:         20 * time.Second,
	}
	client, err := ssh.Dial("tcp", net.JoinHostPort(c.Host, strconv.Itoa(port)), cfg)
	if err != nil {
		if hostKeyErr != nil {
			return nil, hostKeyErr
		}
		if strings.Contains(err.Error(), "unable to authenticate") {
			return nil, &tunnelError{"auth", err}
		}
		return nil, &tunnelError{"connect", err}
	}

	// Без трафіку проміжні маршрутизатори рвуть «тихі» з'єднання — шлемо keepalive.
	go func() {
		for range time.Tick(30 * time.Second) {
			if _, _, err := client.SendRequest("keepalive@openssh.com", true, nil); err != nil {
				return
			}
		}
	}()
	return &sshDialer{client: client}, nil
}
