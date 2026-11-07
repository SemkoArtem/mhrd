//go:build windows

package main

// privateDir: на Windows тека — у %TEMP% профілю користувача, доступ до якого мають лише він і система.
func privateDir(dir string) error { return nil }
