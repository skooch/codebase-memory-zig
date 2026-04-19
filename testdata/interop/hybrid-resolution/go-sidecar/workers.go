package main

type Secondary struct{}

func (Secondary) Handle() {}

type Primary struct{}

func (Primary) Handle() {}
