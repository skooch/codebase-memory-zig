package main

import "fmt"

func greet(name string) string {
	return fmt.Sprintf("hello %s", name)
}

func run() {
	fmt.Println(greet("world"))
}
