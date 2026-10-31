//go:build !windows

package main

import (
	"syscall"
	"time"
)

// На Unix чекати чужий процес не можна — перевіряємо раз на секунду, чи він ще живий.
func waitProcess(pid int) {
	for syscall.Kill(pid, 0) == nil {
		time.Sleep(time.Second)
	}
}
