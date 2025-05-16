#! /bin/sh

# Made by Miguel de las Moras Sastre

##################################################
###############    Definitions    ################
##################################################

# Car traffic light (physical pins 11, 12, 39 for red, yellow, green)
ctr=0    
cta=1
ctv=29
# Pedestrian traffic ligh (physical pins 15, 16 for red, green)
ptr=3
ptv=4
# Other peripherals
but=30 # Button (physical pin 27)
mot=26 # Motor (physical pin 32)

outputs="$ctr $cta $ctv $ptr $ptv"

# Lock files for concurrent functions
lock_prefix=/tmp/semaforo.
lock_extension=.lock
magic_lock_file=${lock_prefix}magic$lock_extension
press_lock_file=${lock_prefix}press_info$lock_extension

##################################################
############    Helpers functions    #############
##################################################

off () {
	gpio write $1 0
}

on () {
	gpio write $1 1
}

range () {
	 gpio pwm $1 $2
}

all() {
	for i in $outputs;do
		$1 $i &
	done
}

##################################################
################    Functions    #################
##################################################

setup() {
	echo Configure and testing interfaces...
	# Configure outputs
	for i in $outputs; do
		gpio mode $i out
		on $i &
	done
	# Configure motor
	gpio mode $mot pwm
	range $mot 50 
	gpio pwm-ms
	gpio pwmr 100
	# Configure button
	gpio mode $but in
	# Delay and stop all
	sleep .7
	range $mot 0 & all off
}

init() {
	on $ctv & on $ptr
}

action () {
	# a. Button pressed (car tl change from green to yellow)
	off $ctv & on $cta & sleep 1
	# b. After a second (car tl change from yellow to red)
	off $cta & on $ctr & sleep 1
	# c. After a second (pedestrian tl change from red to green)
	off $ptr & on $ptv & sleep 0.2
	# After a half second (pedestrians start walking)
	range $mot 50 & sleep 3.8
	# d. After four seconds (the tls -car's yellow and pedestrian's green- start to blink)
	off $ctr & on $cta
	# And pedestrians start to running
	range $mot 100 & sleep .1
	for _ in $(seq 3); do
		off $cta & off $ptv & sleep .5
		on $cta & on $ptv & sleep .5
	done
	# After 7 seconds (pedestrian tl change from green to red)
	# Pedestrians stop running
	range $mot 0 & off $ptv & on $ptr & sleep 1
	# After a second (car tl change from yellow to red)
	off $cta & on $ctv
}

magic () {
	while [ -e $magic_lock_file ]; do
		range $mot 100 & all on & sleep $1
		range $mot 0 & all off & sleep $1
	done
}

test_mode () {
	touch $magic_lock_file
	magic .5 &
	while [ `gpio read $but` = 1 ]; do 
		sleep .1; 
	done
	rm $magic_lock_file
	init 
	# a little delay to ensure the button is released
	sleep .5
}

shutdown() {
	echo Shutting down devices
	all off
	range $mot 0
	rm -f $magic_lock_file
	rm -f $press_lock_file
	exit 0
}

##################################################
############    Trap for Ctrl + c    #############
##################################################

### Safe to shutdown devices before unexpected stop (SIGINT or Ctrl + c)
trap 'shutdown' SIGINT


##################################################
################    Execution    #################
##################################################
setup
init & echo Listo!

while true; do
	# Wait until to button press
	while [ `gpio read $but` = 1 ]; do sleep .1; done
	echo "Button pressed"
	
	touch $press_lock_file
	press_info & start=$(date +%s)
	while [ `gpio read $but` = 0 ]; do sleep .1; done
	end=$(date +%s)
	time=$(( $end - $start ))
	rm $press_lock_file
	echo "Button released ($time seg)"

	if [ $time -le 2 ]; then
		action
	elif [ $time -le 4 ]; then
		test_mode
	else
		echo "RAINBOW"
	fi
done
