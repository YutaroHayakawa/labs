#!/bin/sh

cur=$(pwd)

for lab in labs/*
do
	cd $lab
	./lab.sh deploy
	./lab.sh smoke_test
	./lab.sh destroy
	cd $cur
done
