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

# flags
yellow_blink=1

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
  command="$1"
  shift
	for i in $outputs;do
    $@
		$command $i &
	done
}

##################################################
################    Functions    #################
##################################################

setup() {
	echo Configure and testing interfaces...
	# Configure outputs
  all on gpio mode $i out
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
	off $ctr & { [ $yellow_blink = 0 ] && on $cta } & range $mot 100 & sleep .1
	for _ in $(seq 3); do
		{ [ $yellow_blink = 0 ] && off $cta } & off $ptv & sleep .5
		{ [ $yellow_blink = 0 ] && on $cta } & on $ptv & sleep .5
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

rainbow() {
  all off
  all on sleep 0.5
  all off sleep 0.5
  f=0.7
  f2=.5
  while true; do
    for i in $outputs; do
      { on $i && sleep $f && off $i } &
      sleep $f2
    done
  done
}

alter_yellow_blink_mode() {
  rainbow
}

safe_shutdown() {
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
trap 'safe_shutdown' SIGINT


##################################################
################    Execution    #################
##################################################
setup
init & echo Listo!

while true; do
	# Wait until to button press
	while [ `gpio read $but` = 1 ]; do sleep .1; done
	echo "Button pressed"
	
	mode=0
	start=$(date +%s)
	while [ `gpio read $but` = 0 ]; do 
		sleep .1
		end=$(date +%s)
		time=$(( $end - $start ))
		if [ $mode = 0 ] && [ $time -ge 2 ]; then 
			echo TEST MODE ACTIVATE
			mode=1
		elif [ $mode = 1 ] && [ $time -ge 4 ]; then 
			echo RAINBOW MODE ACTIVATE
			mode=2
		fi
	done
	end=$(date +%s)
	time=$(( $end - $start ))
	echo "Button released ($time seg)"

	case $mode in 
		0)
			action 
			;;
		1)
			test_mode
			;;
    2)
      alter_yellow_blink_mode
      ;;
		*)
			echo RAINBOW
			;;
	esac
done
