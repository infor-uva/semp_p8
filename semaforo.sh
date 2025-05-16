#! /bin/sh

# Made by Miguel de las Moras Sastre

##################################################
###############    Definitions    ################
##################################################

# Car traffic light (physical pins 11, 12, 40 for red, yellow, green)
ctr=0
cty=1
ctg=29
# Pedestrian traffic light (physical pins 15, 16 for red, green)
ptr=3
ptg=4
# Other devices
buz=5  # Buzzer (physical pin 18)
but=30 # Button (physical pin 27)
mot=26 # Motor (physical pin 32)

leds="$ctr $cty $ctg $ptr $ptg"
devices="$leds $buz"

# Lock files for concurrent functions

test_lock_file=$(lock_file test)
rainbow_lock_file=$(lock_file rainbow)
fantastic_car_lock_file=$(lock_file fantastic_car)

# flags
yellow_blink=1

##################################################
############    Helpers functions    #############
##################################################

lock_file() {
  echo "/tmp/semaforo.$1.lock"
}

off() {
  gpio write $1 0
}

on() {
  gpio write $1 1
}

range() {
  gpio pwm $1 $2
}

mode() {
  gpio mode $2 $1
}

all() {
  for i in $devices; do
    $@ $i &
  done
}

##################################################
################    Functions    #################
##################################################

setup() {
  echo Configure and testing interfaces...
  # Configure outputs
  all mode out
  # Configure motor
  mode pwm $mot
  gpio pwm-ms
  gpio pwmr 100
  # Configure button
  mode in $but
}

init() {
  on $ctg &
  on $ptr
}

action() {
  # a. Button pressed (car tl change from green to yellow)
  off $ctg &
  on $cty &
  sleep 1
  # b. After a second (car tl change from yellow to red)
  off $cty &
  on $ctr &
  sleep 1
  # c. After a second (pedestrian tl change from red to green)
  off $ptr &
  on $ptg &
  sleep 0.2
  # After a half second (pedestrians start walking)
  range $mot 50 &
  sleep 3.8
  # d. After four seconds (the tls -car's yellow and pedestrian's green- start to blink)
  off $ctr &
  { [ $yellow_blink = 0 ] && on $cty; } &
  range $mot 100 &
  sleep .1
  for _ in $(seq 3); do
    { [ $yellow_blink = 0 ] && off $cty; } &
    off $ptg &
    sleep .5
    { [ $yellow_blink = 0 ] && on $cty; } &
    on $ptg &
    sleep .5
  done
  # After 7 seconds (pedestrian tl change from green to red)
  # Pedestrians stop running
  range $mot 0 &
  off $ptg &
  on $ptr &
  sleep 1
  # After a second (car tl change from yellow to red)
  off $cty &
  on $ctg
}

test_devices() {
  while [ -e $test_lock_file ]; do
    range $mot 100 &
    all on &
    sleep $1
    range $mot 0 &
    all off &
    sleep $1
  done
}

test_mode() {
  touch $test_lock_file
  test_devices .5 &
  while [ $(gpio read $but) = 1 ]; do
    sleep .1
  done
  rm $test_lock_file
  init
  # a little delay to ensure the button is released
  sleep .5
}

rainbow() {
  liv=1
  frc=.5
  while true; do
    for i in $leds; do
      { on $i && sleep $liv && off $i; } &
      sleep $frc
    done
  done
}

x_rainbow() {
  liv=1
  frc=.5
  while true; do
    {
      on $ctr &
      on $ptg &
      sleep $liv && off $ctr &
      off $ptg
    } &
    sleep $frc
    {
      on $cty &
      on $ptr &
      sleep $liv && off $cty &
      off $ptr
    } &
    sleep $frc
    {
      on $ctg &
      sleep $liv && off $ctg
    } &
    sleep $frc
    {
      on $cty &
      on $ptr &
      sleep $liv && off $cty &
      off $ptr
    } &
    sleep $frc
  done
}

fantastic_car() {
  liv=1
  frc=.5
  while true; do
    for i in "$ctr $cty $ctg $ptr $ptg $ptr $ctg $cty"; do
      { on $i && sleep $liv && off $i; } &
      sleep $frc
    done
  done
}

safe_shutdown() {
  echo Shutting down devices
  all off
  range $mot 0
  rm -f $test_lock_file
  rm -f $rainbow_lock_file
  rm -f $fantastic_car_lock_file
  exit 0
}

##################################################
############    Trap for Ctrl + c    #############
##################################################

### Safe to shutdown devices before unexpected stop (SIGINT or Ctrl + c)
trap safe_shutdown SIGINT

##################################################
################    Execution    #################
##################################################
setup
init &
echo Listo!

while true; do
  # Wait until to button press
  while [ $(gpio read $but) = 1 ]; do sleep .1; done
  echo "Button pressed"

  mode=0
  start=$(date +%s)
  while [ $(gpio read $but) = 0 ]; do
    sleep .1
    end=$(date +%s)
    time=$(($end - $start))
    if [ $mode = 0 ] && [ $time -ge 2 ]; then
      echo ALTER CUSTOM BLINK
      mode=1
    elif [ $mode = 1 ] && [ $time -ge 4 ]; then
      echo RAINBOW MODE ACTIVATE
      mode=2
    elif [ $mode = 2 ] && [ $time -ge 6 ]; then
      echo X-RAINBOW MODE ACTIVATE
      mode=3
    elif [ $mode = 3 ] && [ $time -ge 8 ]; then
      echo FANTASTIC CAR MODE ACTIVATE
      mode=4
    elif [ $mode = 4 ] && [ $time -ge 10 ]; then
      echo TEST MODE ACTIVATE
      mode=5
    fi
  done
  end=$(date +%s)
  time=$(($end - $start))
  echo "Button released ($time seg)"

  case $mode in
  0)
    action
    ;;
  1)
    echo "alter"
    ;;
  2)
    rainbow
    ;;
  3)
    x_rainbow
    ;;
  4)
    fantastic_car
    ;;
  5)
    test_devices
    ;;
  esac
done
