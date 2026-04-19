package main

type Primary struct{}

func (Primary) Handle() {}

type Worker struct{}

func (Worker) Handle() {}
