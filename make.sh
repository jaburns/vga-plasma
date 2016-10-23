#!/usr/bin/env bash

if [[ "$1" == 'clean' ]]; then
    rm *.hex *.out
    exit
fi

avr-as -mmcu=atmega328p -o prog.out main.s
avr-objcopy -O ihex prog.out prog.hex
# avrdude -p m328p -c stk500 -e -U flash:w:prog.hex
