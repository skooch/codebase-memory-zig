package main

import "fmt"

type Runner interface {
	Run() string
}

type Config struct {
	Mode    string
	Verbose bool
}

type Worker struct {
	Config Config
}

func (w *Worker) Run() string {
	return fmt.Sprintf("running in %s mode", w.Config.Mode)
}

func NewWorker(mode string) *Worker {
	return &Worker{Config: Config{Mode: mode, Verbose: false}}
}

func boot() string {
	w := NewWorker("batch")
	return w.Run()
}
