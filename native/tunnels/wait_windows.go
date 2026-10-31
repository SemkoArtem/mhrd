//go:build windows

package main

import "os"

// На Windows os.FindProcess відкриває дескриптор, і Wait чекає навіть не свого нащадка.
func waitProcess(pid int) {
	p, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	p.Wait()
}
