//go:build !windows

package main

import (
	"fmt"
	"os"
	"syscall"
)

// privateDir — тека «візиток» лише для цього користувача: власник — ми, інші не мають доступу.
// У спільному /tmp її міг би заздалегідь створити хтось інший — тоді токен був би видний йому.
func privateDir(dir string) error {
	fi, err := os.Lstat(dir)
	if err != nil {
		return err
	}
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !fi.IsDir() || !ok || int(st.Uid) != os.Getuid() || fi.Mode().Perm()&0o077 != 0 {
		return fmt.Errorf("state dir %s is not private", dir)
	}
	return nil
}
