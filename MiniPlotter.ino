/*
 * Arduino code for the mini plotter.
 * 2017 hackaday prize entry "upgrade for your diy pen plotters"
 * by shlonkin
 * 
 * Two DVD drives, one servo
 * This cude is kind of limited to my particular setup
 * and may require significant modification to work with
 * your machine.
 */

 #include <Servo.h>

// 400=29.95x
// 400 = 29.25y

////////////////////////////////////////////////////////////////////////////////
// Set these variables to match your setup                                  ////
////////////////////////////////////////////////////////////////////////////////
// step parameters                                                          ////
float stepSize[2] = {13.3556, 13.675}; // steps per mm [x, y]       ////
float mmPerStep[2] = {0.07487, 0.073126}; // mm per step[x, y]
int fastDelay[3] = {1, 1}; // determines movement speed by             ////
int slowDelay[3] = {3, 3}; // delaying ms after each step            ////
// enable and phase pins for each motor                                     ////
// this is for two-winding bipolar steppers                                 ////
const uint8_t e1[2] = {2, 8}; // winding 1 [x, y]                         ////
const uint8_t p11[2] = {3, 10};                                             ////
const uint8_t p12[2] = {4, 11};                                             ////
const uint8_t e2[2] = {5, 12}; // winding 2                                ////
const uint8_t p21[2] = {6, 13};                                              ////
const uint8_t p22[2] = {7, 14};                                              ////
// Pen lifting servo uses pwm
const uint8_t penPin = 9;
// button for manually raising and lowering for setting pen position
const uint8_t adjButton = 15;
// The angles for raised and lowered positions
uint8_t penRaise = 60;
uint8_t penLower = 90;
int penMoveDelay = 150;
// the serial rate                                                          ////
#define SRATE 9600
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

Servo penServo;

// the current motor states
uint8_t mstate[2]; // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
bool penDown; // true when pen is down
bool moveFast; // when true, fast delay is used(motion is faster)
bool started;

// position variables
int poss[2]; // position in motor steps (x,y)
float posmm[2]; // position in mm (x,y)

void setup() {
  // enable pins
  pinMode(e1[0], OUTPUT);
  digitalWrite(e1[0], LOW);
  pinMode(e1[1], OUTPUT);
  digitalWrite(e1[1], LOW);
  pinMode(e2[0], OUTPUT);
  digitalWrite(e2[0], LOW);
  pinMode(e2[1], OUTPUT);
  digitalWrite(e2[1], LOW);
  // phase pins
  pinMode(p11[0], OUTPUT);
  digitalWrite(p11[0], LOW);
  pinMode(p11[1], OUTPUT);
  digitalWrite(p11[1], LOW);
  pinMode(p21[0], OUTPUT);
  digitalWrite(p21[0], LOW);
  pinMode(p21[1], OUTPUT);
  digitalWrite(p21[1], LOW);
  pinMode(p12[0], OUTPUT);
  digitalWrite(p12[0], LOW);
  pinMode(p12[1], OUTPUT);
  digitalWrite(p12[1], LOW);
  pinMode(p22[0], OUTPUT);
  digitalWrite(p22[0], LOW);
  pinMode(p22[1], OUTPUT);
  digitalWrite(p22[1], LOW);
  // servo pin
  penServo.attach(penPin);
  // button pin
  pinMode(adjButton, INPUT_PULLUP);
  
  penServo.write(penRaise);
  delay(penMoveDelay);
  penDown = false;
  moveFast = false;
  started = false;

  // variables
  poss[0] = 0;
  poss[1] = 0;
  posmm[0] = 0.0;
  posmm[1] = 0.0;
  mstate[0] = 0;
  mstate[1] = 0;

  Serial.begin(SRATE);

  // wait for processing to connect
  bool waiting = true;
  while(waiting){
    if(Serial.available()>0){
      if(Serial.read() == '#'){
        Serial.write('@');
        waiting = false;
      }
    }
    // if the button is pressed, handle it
    if(digitalRead(adjButton) == LOW){
      if(penDown){
        penServo.write(penRaise);
        delay(penMoveDelay);
        penDown = false;
      }else{
        penServo.write(penLower);
        delay(penMoveDelay);
        penDown = true;
      }
      // wait for button release
      while(digitalRead(adjButton) == LOW);
      delay(100);
    }
  }
  digitalWrite(13, LOW);
  // flush serial
  while(Serial.available()>0){
    Serial.read();
  }
  
}

void loop() {
  // wait for data to come
  while(Serial.available() < 1);
  // then handle it
   // the char '#' is a comm check. reply with '@'
  // start if the char 'S' is sent, finish if 'T' is sent
  char incoming = Serial.peek();
  if(incoming == '#'){
    Serial.read();
    Serial.write('@');
  }else if(incoming == 'S'){
    // drawing started
    started = true;
    Serial.read();
  }else if(incoming == 'F'){
    // drawing finished
    started = false;
    Serial.read();
    penServo.write(penRaise);
    delay(penMoveDelay);
    penDown = false;
    drawLine(0.0, 0.0);
    posmm[0] = 0.0;
    posmm[1] = 0.0;
    poss[0] = 0;
    poss[1] = 0;
  }else if(incoming == 'U'){
    // raise pen
    Serial.read();
    if(penDown){
      penServo.write(penRaise);
      delay(penMoveDelay);
      penDown = false;
    }
    Serial.write(7);
  }else if(incoming == 'D'){
    // lower pen
    Serial.read();
    if(!penDown){
      penServo.write(penLower);
      delay(penMoveDelay);
      penDown = true;
    }
    Serial.write(7);
  }else if(started){
    // if there is some serial data, read it, parse it, use it
    float newx = receiveNumber();
    // wait for the y data
    float newy = receiveNumber();
    // now we have newx and newy. 
    drawLine(newx, newy);
  }else{
    // it was some unexpected transmission
    // clear it
    Serial.read();
  }
}

float receiveNumber(){
  boolean complete = false;
  char tmpchar;
  uint8_t charcount = 0;
  float thenumber = 0;
  int sign = 1;
  while(!complete){
    // wait for data
    while(Serial.available() < 1);
    tmpchar = Serial.read();
    if(tmpchar == '.'){ // signals end of number
      complete = true;
      continue;
    }
    if(tmpchar == '-'){
      sign = -1;
    }else{
      thenumber = thenumber*10.0 + tmpchar-'0';
    }
    charcount++;
  }
  thenumber = thenumber*sign/10000.0;
  Serial.write(charcount); // send verification byte
  return thenumber;
}

/*
* moves in a straight line from the current position
* to the point (x2, y2)
*/
void drawLine(float x2, float y2){
  long xSteps, ySteps;
  int8_t xdir, ydir;
  float slope;
  long dx, dy;
  // determine the direction and number of steps
  xdir = 1;
  if(x2-posmm[0] < 0 ) xdir = -1;
  xSteps = long(x2*stepSize[0] - posmm[0]*stepSize[0] + 0.5*xdir);
  
  ydir = 1;
  if(y2-posmm[1] < 0) ydir = -1;
  ySteps = long(y2*stepSize[1] - posmm[1]*stepSize[1] + 0.5*ydir);
  
  if(xSteps*xdir > 0){
    slope = ySteps*1.0/(1.0*xSteps)*ydir*xdir;
  }else{
    slope = 100000;
  }
  dx = 0;
  dy = 0;

  if(xSteps*xdir > ySteps*ydir){
    while(dx < xSteps*xdir){
      // move one x step at a time
      dx++;
      oneStep(0, xdir);
      // if needed, move y one step
      if(ySteps*ydir > 0 && (slope*dx)-0.5 > dy){
        dy++;
        oneStep(1, ydir);
      }
    }
  }
  else{
    while(dy < ySteps*ydir){
      // move one y step at a time
      dy++;
      oneStep(1, ydir);
      // if needed, move x one step
      if(xSteps*xdir > 0 && dy > slope*(dx+0.5)){
        dx++;
        oneStep(0, xdir);
      }
    }
  }
  // finish up any remaining steps
  while(dx < xSteps*xdir){
    // move one x step at a time
    dx++;
    oneStep(0, xdir);
  }
  while(dy < ySteps*ydir){
    // move one y step at a time
    dy++;
    oneStep(1, ydir);
  }
  // at this point we have drawn the line
}

void oneStep(int m, int dir){
  // make one step with motor number m in direction dir
  // then delay for speed control
  // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
  if(dir > 0){
    poss[m]++;
    posmm[m] += mmPerStep[m];
    if(mstate[m] ==0){
      digitalWrite(p21[m], LOW);
      digitalWrite(p22[m], HIGH);
      digitalWrite(e2[m], HIGH);
      mstate[m] = 1;
    }
    else if(mstate[m] ==1){
      digitalWrite(e1[m], LOW);
      mstate[m] = 2;
    }
    else if(mstate[m] ==2){
      digitalWrite(p11[m], LOW);
      digitalWrite(p12[m], HIGH);
      digitalWrite(e1[m], HIGH);
      mstate[m] = 3;
    }
    else if(mstate[m] ==3){
      digitalWrite(e2[m], LOW);
      mstate[m] = 4;
    }
    else if(mstate[m] ==4){
      digitalWrite(p21[m], HIGH);
      digitalWrite(p22[m], LOW);
      digitalWrite(e2[m], HIGH);
      mstate[m] = 5;
    }
    else if(mstate[m] ==5){
      digitalWrite(e1[m], LOW);
      mstate[m] = 6;
    }
    else if(mstate[m] ==6){
      digitalWrite(p11[m], HIGH);
      digitalWrite(p12[m], LOW);
      digitalWrite(e1[m], HIGH);
      mstate[m] = 7;
    }
    else if(mstate[m] ==7){
      digitalWrite(e2[m], LOW);
      mstate[m] = 0;
    }
  }
  else{
    // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
    poss[m]--;
    posmm[m] -= mmPerStep[m];
    if(mstate[m] ==0){
      digitalWrite(p21[m], HIGH);
      digitalWrite(p22[m], LOW);
      digitalWrite(e2[m], HIGH);
      mstate[m] = 7;
    }
    else if(mstate[m] ==1){
      digitalWrite(e2[m], LOW);
      mstate[m] = 0;
    }
    else if(mstate[m] ==2){
      digitalWrite(p11[m], HIGH);
      digitalWrite(p12[m], LOW);
      digitalWrite(e1[m], HIGH);
      mstate[m] = 1;
    }
    else if(mstate[m] ==3){
      digitalWrite(e1[m], LOW);
      mstate[m] = 2;
    }
    else if(mstate[m] ==4){
      digitalWrite(p21[m], LOW);
      digitalWrite(p22[m], HIGH);
      digitalWrite(e2[m], HIGH);
      mstate[m] = 3;
    }
    else if(mstate[m] ==5){
      digitalWrite(e2[m], LOW);
      mstate[m] = 4;
    }
    else if(mstate[m] ==6){
      digitalWrite(p11[m], LOW);
      digitalWrite(p12[m], HIGH);
      digitalWrite(e1[m], HIGH);
      mstate[m] = 5;
    }
    else if(mstate[m] ==7){
      digitalWrite(e1[m], LOW);
      mstate[m] = 6;
    }
  }
  if(moveFast){
    delay(fastDelay[m]);
  }else{
    delay(slowDelay[m]);
  }
}
