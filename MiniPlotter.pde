/**
 *  Processing sketch for the MiniPlotter
 *  Based on the SVG to (x,y) code from the SVGMill
 *  
 *  This can use SVG images to draw paths or use PNG images to hatch grayscale.
 *  Both can be done at the same time.
 *  SVG mode: Reads an SVG image file, converts the path data into 
 *  a list of coordinates, then sends the coordinates
 *  over the serial connection to an arduino.
 *  Does not yet support "transform" commands.
 *  NOTE: The arduino must have a compatible program. 
 *  (see sendData() method below)
 *  PNG mode: generates a set of straight line hatches depending on darkness.
 *  
 *  /////////////////// How to use: ///////////////////////////////////
 *  1. Set file path, image type, and any parameters you want below.
 *  2. Run the sketch. It should open a window and display the result.
 *  3. Use number keys to set the number of hatch levels(1-9).
 *  4. Use up and down arrow keys to adjust the thresholds.
 *  5. Pressing "d" will attempt to send the coordinates via serial
 *
 *  ///////////////////////////////////////////////////////////////////
 *  
 *  2017 Eric Heisler
 *  This program is in the public domain. Do what you will with it.
 */
import processing.serial.*;

//////////////////////////////////////////////
// Set these variables directly before running
//////////////////////////////////////////////
String serialPort = "COM3"; // the name of the USB port
int serialRate = 115200; // serial rate, duh
boolean connected = false; // true after connected to arduino
int imageType = 0; // 0=svg, 1=png, 2=both
boolean fileSelectedRun;
String filePath = "data/disco.svg"; // the SVG file path
String pngPath = "data/t2.png"; // png file path
double precision = .2; // precision for interpolating curves (smaller = finer)
float maxdim = 30; // maximum dimension in mm (either height or width)
boolean rotated = true; // true rotates 90 degrees: (maxy-y)->x, x->y
boolean sendIt = false; // true=sends the data, false=just draws to screen
boolean useHatches = false; // to generate hatches for filling
int hatchLevels = 4; // the number of hatch levels for grayscale
float hatchSlope = -1; // negative to slant up to the right
float hatchInterval = 0.02; // multiplied by maxdim to give interval in mm
int hatchThreshold = 127; // anything below this value will be hatched
int hatchThresholdMax = 200; // max of the range when using multiple hatches
float minHatchLength = 0.1; // don't draw too short hatches

ArrayList<Point> allpoints;
ArrayList<Integer> penMoves;
boolean penDown;
int vectorPointCount, vectorPenCount;

boolean workFinished, generatePoints;
PShape svgShape;
float maxx, maxy, minx, miny;
int pixWidth, pixHeight;
boolean hatchesReady;

PrintWriter output;

Serial sPort; 

void setup() {
  size(400, 400);
  allpoints = new ArrayList<Point>();
  penMoves = new ArrayList<Integer>();
  penDown = false;
  workFinished = false;
  generatePoints = true;
  hatchesReady = false;
  vectorPointCount = 0;
  // In SVG mode, read the data file
  // This is only done once, so it is in setup()
  if(imageType == 0 || imageType == 2){
    // select the image file
    filePath = null;
    while(filePath == null){
      fileSelectedRun = false;
      selectInput("Select an image file", "fileSelected", new File(sketchPath("select an image file")));
      println("waiting");
      while(!fileSelectedRun){
        delay(500);
        print(".");
      }
      println("waiting2");
    }
    println("file selected");
    readData(filePath);
    vectorPointCount = allpoints.size();
    vectorPenCount = penMoves.size();
    if (allpoints.size()==0) {
      println("There was an error in the data file");
      while(true);
    }
  }else{
    // other mode must use hatches
    useHatches = true;
    // and the size needs to be found
    minx = 0;
    miny = 0;
    PImage im = loadImage(pngPath);
    if(im.width > im.height){
      maxx = maxdim;
      maxy = (im.height*maxdim)/im.width;
    }else{
      maxy = maxdim;
      maxx = (im.width*maxdim)/im.height;
    }
  }
  
  // connect to the arduino if needed
  // NOTE this is now done when the 'd' key is pressed later
  /*
  if(sendIt){
    sPort = new Serial(this, serialPort, 9600);
    if(sPort==null){
      println("couldn't find serial port");
    }else{
      // delay in case the arduino reset 
      delay(1000);
    }
  }
  */
  svgShape = loadShape(filePath);
}

void draw() {
  // only recompute things when needed
  if(generatePoints){
    generatePoints = false;
    // if hatches were previously found, discard them and recompute
    if(allpoints.size() > vectorPointCount){
      for(int i=allpoints.size()-1; i>=vectorPointCount; i--){
        allpoints.remove(i);
      }
    }
    if(penMoves.size() > vectorPenCount){
      for(int i=penMoves.size()-1; i>=vectorPenCount;  i--){
        penMoves.remove(i);
      }
    }
     // draw a picture of what it should look like on the screen
    makePicture();
    if(useHatches){
      // clear the window, load image, make hatches, clear the window, redraw
      loadPixels();
      for(int i=0; i<pixels.length; i++){
        pixels[i] = color(255);
      }
      updatePixels();
      // load svg image
      if(maxy-miny > maxx-minx){
        pixWidth = int((maxx-minx)*(height*1.0/(maxy-miny)));
        pixHeight = height;
      }else{
        pixWidth = width;
        pixHeight = int((maxy-miny)*(width*1.0/(maxx-minx)));
      }
      if(imageType == 1 || imageType == 2){
        image(loadImage(pngPath), 0, 0, pixWidth, pixHeight);
      }else{
        shape(svgShape, 0, 0, pixWidth, pixHeight);
      }
      
      loadPixels();
      
      // make hatches
      if(hatchLevels > 1){
        float slopes[] = {-3, 3, 0.001, -1.5, 1.5, -0.75, 2.25, -2.25, 0.75, 0.3};
        int varthresh = 200;
        if(hatchLevels > 10){
          hatchLevels = 10;
        }
        for(int i=0; i<hatchLevels; i++){
          varthresh = 20 + ((hatchThresholdMax-20)*(i+1))/hatchLevels;
          makeHatches(hatchInterval, slopes[i], varthresh);
        }
      }else{
        makeHatches(hatchInterval, hatchSlope, hatchThreshold);
      }
      
      // clear the window
      for(int i=0; i<pixels.length; i++){
        pixels[i] = color(255);
      }
      updatePixels();
      // redraw with hatches
      makePicture();
    }
  }else{
    // draw a picture of what it should look like on the screen
    makePicture();
  }
  
  // it's ready to send
  workFinished = true;
  
}

void fileSelected(File f){
  println("fs");
  if(f != null){
    filePath = f.getName();
  }
  fileSelectedRun = true;
  println("fs2");
}

void keyPressed(){
  // arrow keys change threshold maximum
  if(keyCode == UP){
    hatchThresholdMax += 5;
    if(hatchThresholdMax > 255){
      hatchThresholdMax = 255;
    }
    if(hatchLevels == 1){
      hatchThreshold = hatchThresholdMax;
    }
  }else if(keyCode == DOWN){
    hatchThresholdMax -= 5;
    if(hatchThresholdMax < 25){
      hatchThresholdMax = 25;
    }
    if(hatchLevels == 1){
      hatchThreshold = hatchThresholdMax;
    }
  }else if(key >= '1' && key <= '9'){
    hatchLevels = key - '1' + 1;
  }else if(key == 'd'){
    // send the current drawing to the arduino
    if(!workFinished){
      println("not finished drawing");
    }else{
      // write it serially to the usb port to be read by the arduino
      sendData();
    }
    // don't regenerate
    return;
  }
  generatePoints = true;
  println("pressed"+key);
}

// reads the file
void readData(String fileName) {
  
  int ind = -1;
  int indr = -1;
  boolean isRect = false;
  boolean hasTrans = false;
  int transLine = 0;
  boolean foundPath = false;
  boolean foundPData = false;
  String pstring = null; // holds the full path data in a string
  String[] pdata = null; // each element of the path data
  Point relpt = new Point(0.0, 0.0); // for relative commands
  Point startpt = new Point(0.0, 0.0); // for z commands
  
  // read all lines into an array
  String lines[] = loadStrings(fileName);
  if(lines == null){
    println("error reading file");
    return;
  }
  
  // wrap everything in a huge try block. Yes, I know this is not ideal.
  try{
    // search lines one by one to pick out path data
    for(int lind=0; lind<lines.length; lind++){
      // search for the beginning of a path: "<path" or a rect: "<rect"
      if(!foundPath){
        ind = lines[lind].indexOf("<path");
        indr = lines[lind].indexOf("<rect");
        // one of these should always be <0
        if(ind >= 0){
          isRect = false;
          foundPath = true;
          hasTrans = false;
        }else if(indr >= 0){
          isRect = true;
          foundPath = true;
          hasTrans = false;
        }else{
          continue;
        }
      }
      
      // if we got here, we found either a path or rect
      if(isRect){
        //we found a rect. This only has 4 important numbers
        //search lines until they are all found
        int remainingPars = 4;
        double rectx = 0.0;
        double recty = 0.0;
        double rectwidth = 0.0;
        double rectheight = 0.0;
        while(remainingPars > 0){
          //keep an eye out for transforms
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          
          if(lines[lind].indexOf("width=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("width=\"") + 7);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectwidth = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("height=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("height=\"") + 8);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectheight = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("x=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("x=\"") + 3);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectx = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("y=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("y=\"") + 3);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            recty = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(remainingPars > 0){
            lind++;
          }
        }
        // now all rect parameters are found. build a path
        ArrayList<Point> pathpoints = new ArrayList<Point>();
        // lift and lower the pen
        penMoves.add(allpoints.size()+pathpoints.size());
        penMoves.add(-allpoints.size()-pathpoints.size()-1);
        // the start point is the upper left (x,y)
        pathpoints.add(new Point(rectx, recty));
        // lets go clockwise
        pathpoints.add(new Point(rectx+rectwidth, recty));
        pathpoints.add(new Point(rectx+rectwidth, recty+rectheight));
        pathpoints.add(new Point(rectx, recty+rectheight));
        pathpoints.add(new Point(rectx, recty));
        
        // here we have completed this rect. Yay!
        // read lines till we reach the true end of rect "/>"
        while(lines[lind].indexOf("/>") < 0){
          // there could still be a transform in there!
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          lind++;
        }
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        
        // if there was a transform, apply it to the path
        if(hasTrans){
          // translate all points by this much
          pstring = lines[lind].substring(lines[lind].indexOf("translate(") + 10);
          pstring = pstring.substring(0, pstring.indexOf(")"));
          pdata = splitTokens(pstring, ", \t");
          double transx = Double.valueOf(pdata[0]).doubleValue();
          double transy = 0.0;
          Point tmppoint;
          if(pdata.length > 1){
            transy = Double.valueOf(pdata[1]).doubleValue();
          }
          for(int arrayind=0; arrayind<pathpoints.size(); arrayind++){
            tmppoint = pathpoints.get(arrayind);
            pathpoints.set(arrayind, new Point(tmppoint.x+transx, tmppoint.y+transy));
          }
        }
        
        allpoints.addAll(pathpoints);
        foundPath = false;
        println("subpath complete, points: "+String.valueOf(pathpoints.size()));
        
      }else{
        // we found a path. Now search for the path data
        // NOTE: this will typically work for Inkscape and Gimp. 
        // Not guaranteed to work for all SVG editors
        if(!foundPData){
          ind = lines[lind].indexOf("d=\"M ");
          if(ind < 0){
            ind = lines[lind].indexOf("d=\"m ");
            if(ind < 0){
              continue;
            }else{
              foundPData = true;
              ind = lines[lind].indexOf('m');
            }
          }else{
            foundPData = true;
            ind = lines[lind].indexOf('M');
          }
        }
        // now we are on the first line of path data
        // let's read in the whole path data into one long string bastard
        //keep an eye out for transforms
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        pstring = lines[lind].substring(ind);
        if(pstring.indexOf("\"") >= 0){
          foundPData = false;
          pstring = pstring.substring(0, pstring.indexOf("\""));
        }
        while(foundPData){
          lind++;
          pstring = pstring + lines[lind];
          if(pstring.indexOf("\"") >= 0){
            foundPData = false;
            pstring = pstring.substring(0, pstring.indexOf("\""));
          }
          //keep an eye out for transforms
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
        }
        // now split the string into parts
        pdata = splitTokens(pstring, ", \t");
        
        // now the task of parsing and interpolating
        int mode = -1; // 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 = M,m,L,l,H,h,V,v,C,c,S,s,A,a,Z,z
        Point cntrlpt = null; // special point for s commands
        ArrayList<Point> pathpoints = new ArrayList<Point>();
        for(int i=0; i<pdata.length; i++){
          if(mode == 0){ mode = 2; }  // only one M/m command at a time
          if(mode == 1){ mode = 3; }
          if(pdata[i].charAt(0) == 'M'){
            mode = 0;
            i++;
          }else if(pdata[i].charAt(0) == 'm'){
            mode = 1;
            i++;
          }else if(pdata[i].charAt(0) == 'L'){
            mode = 2;
            i++;
          }else if(pdata[i].charAt(0) == 'l'){
            mode = 3;
            i++;
          }else if(pdata[i].charAt(0) == 'H'){
            mode = 4;
            i++;
          }else if(pdata[i].charAt(0) == 'h'){
            mode = 5;
            i++;
          }else if(pdata[i].charAt(0) == 'V'){
            mode = 6;
            i++;
          }else if(pdata[i].charAt(0) == 'v'){
            mode = 7;
            i++;
          }else if(pdata[i].charAt(0) == 'C'){
            mode = 8;
            i++;
          }else if(pdata[i].charAt(0) == 'c'){
            mode = 9;
            i++;
          }else if(pdata[i].charAt(0) == 'S'){
            if(mode < 8 || mode > 11){
              cntrlpt = relpt;
            }
            mode = 10;
            i++;
          }else if(pdata[i].charAt(0) == 's'){
            if(mode < 8 || mode > 11){
              cntrlpt = relpt;
            }
            mode = 11;
            i++;
          }else if(pdata[i].charAt(0) == 'Q'){
            mode = 12;
            i++;
          }else if(pdata[i].charAt(0) == 'q'){
            mode = 13;
            i++;
          }else if(pdata[i].charAt(0) == 'T'){
            if(mode < 12 || mode > 15){
              cntrlpt = relpt;
            }
            mode = 14;
            i++;
          }else if(pdata[i].charAt(0) == 't'){
            if(mode < 12 || mode > 15){
              cntrlpt = relpt;
            }
            mode = 15;
            i++;
          }else if(pdata[i].charAt(0) == 'A'){
            mode = 16;
            i++;
          }else if(pdata[i].charAt(0) == 'a'){
            mode = 17;
            i++;
          }else if(pdata[i].charAt(0) == 'Z'){
            mode = 18;
            //i++; don't need this
          }else if(pdata[i].charAt(0) == 'z'){
            mode = 19;
            //i++; don't need this
          }else{
            // repeated commands do not need repeated letters
          }
          
          if(mode == 0){
            // lift and lower the pen
            penMoves.add(allpoints.size()+pathpoints.size());
            penMoves.add(-allpoints.size()-pathpoints.size()-1);
            // this is followed by 2 numbers
            double tmpx = Double.valueOf(pdata[i]).doubleValue();
            double tmpy = Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            startpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 1){
            // lift and lower the pen
            penMoves.add(allpoints.size()+pathpoints.size());
            penMoves.add(-allpoints.size()-pathpoints.size()-1);
            double x = 0.0;
            double y = 0.0;
            if(pathpoints.size() > 0){
              x = relpt.x;
              y = relpt.y;
            }
            // this is followed by 2 numbers
            double tmpx = x + Double.valueOf(pdata[i]).doubleValue();
            double tmpy = y + Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            startpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 2){
            // this is followed by 2 numbers
            double tmpx = Double.valueOf(pdata[i]).doubleValue();
            double tmpy = Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 3){
            // this is followed by 2 numbers
            double tmpx = relpt.x + Double.valueOf(pdata[i]).doubleValue();
            double tmpy = relpt.y + Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 4){
            // this is followed by 1 number
            pathpoints.add(new Point(Double.valueOf(pdata[i]).doubleValue(), relpt.y));
            relpt = new Point(Double.valueOf(pdata[i]).doubleValue(), relpt.y);
          }else if(mode == 5){
            // this is followed by 1 number
            double tmpx = relpt.x + Double.valueOf(pdata[i]).doubleValue();
            pathpoints.add(new Point(tmpx, relpt.y));
            relpt = new Point(tmpx, relpt.y);
          }else if(mode == 6){
            // this is followed by 1 number
            pathpoints.add(new Point(relpt.x, Double.valueOf(pdata[i]).doubleValue()));
            relpt = new Point(relpt.x, Double.valueOf(pdata[i]).doubleValue());
          }else if(mode == 7){
            // this is followed by 1 number
            double tmpy = relpt.y + Double.valueOf(pdata[i]).doubleValue();
            pathpoints.add(new Point(relpt.x, tmpy));
            relpt = new Point(relpt.x, tmpy);
          }else if(mode == 8){
            // this is followed by 6 numbers
            //double x = relpt.x;
            //double y = relpt.y;
            double xc1 = Double.valueOf(pdata[i]).doubleValue();
            double yc1 = Double.valueOf(pdata[i+1]).doubleValue();
            double xc2 = Double.valueOf(pdata[i+2]).doubleValue();
            double yc2 = Double.valueOf(pdata[i+3]).doubleValue();
            double px = Double.valueOf(pdata[i+4]).doubleValue();
            double py = Double.valueOf(pdata[i+5]).doubleValue();
            cntrlpt = new Point(px + px-xc2, py + py-yc2);
            pathpoints.addAll(interpolateCubic(relpt, new Point(xc1, yc1), new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 5;
          }else if(mode == 9){
            // this is followed by 6 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc1 = x + Double.valueOf(pdata[i]).doubleValue();
            double yc1 = y + Double.valueOf(pdata[i+1]).doubleValue();
            double xc2 = x + Double.valueOf(pdata[i+2]).doubleValue();
            double yc2 = y + Double.valueOf(pdata[i+3]).doubleValue();
            double px = x + Double.valueOf(pdata[i+4]).doubleValue();
            double py = y + Double.valueOf(pdata[i+5]).doubleValue();
            cntrlpt = new Point(px + px-xc2, py + py-yc2);
            pathpoints.addAll(interpolateCubic(relpt, new Point(xc1, yc1), new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 5;
          }else if(mode == 10){
            // this is followed by 4 numbers
            //double x = relpt.x;
            //double y = relpt.y;
            double xc2 = Double.valueOf(pdata[i]).doubleValue();
            double yc2 = Double.valueOf(pdata[i+1]).doubleValue();
            double px = Double.valueOf(pdata[i+2]).doubleValue();
            double py = Double.valueOf(pdata[i+3]).doubleValue();
            pathpoints.addAll(interpolateCubic(relpt, cntrlpt, new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
            cntrlpt = new Point(px + px-xc2, py + py-yc2);
          }else if(mode == 11){
            // this is followed by 4 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc2 = x + Double.valueOf(pdata[i]).doubleValue();
            double yc2 = y + Double.valueOf(pdata[i+1]).doubleValue();
            double px = x + Double.valueOf(pdata[i+2]).doubleValue();
            double py = y + Double.valueOf(pdata[i+3]).doubleValue();
            pathpoints.addAll(interpolateCubic(relpt, cntrlpt, new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
            cntrlpt = new Point(px + px-xc2, py + py-yc2);
          }else if(mode == 12){
            // this is followed by 4 numbers
            //double x = relpt.x;
            //double y = relpt.y;
            double xc1 = Double.valueOf(pdata[i]).doubleValue();
            double yc1 = Double.valueOf(pdata[i+1]).doubleValue();
            double px = Double.valueOf(pdata[i+2]).doubleValue();
            double py = Double.valueOf(pdata[i+3]).doubleValue();
            cntrlpt = new Point(px + px-xc1, py + py-yc1);
            pathpoints.addAll(interpolateQuadratic(relpt, new Point(xc1, yc1), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
          }else if(mode == 13){
            // this is followed by 4 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc1 = x + Double.valueOf(pdata[i]).doubleValue();
            double yc1 = y + Double.valueOf(pdata[i+1]).doubleValue();
            double px = x + Double.valueOf(pdata[i+2]).doubleValue();
            double py = y + Double.valueOf(pdata[i+3]).doubleValue();
            cntrlpt = new Point(px + px-xc1, py + py-yc1);
            pathpoints.addAll(interpolateQuadratic(relpt, new Point(xc1, yc1), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
          }else if(mode == 14){
            // this is followed by 2 numbers
            //double x = relpt.x;
            //double y = relpt.y;
            double px = Double.valueOf(pdata[i]).doubleValue();
            double py = Double.valueOf(pdata[i+1]).doubleValue();
            pathpoints.addAll(interpolateQuadratic(relpt, cntrlpt, new Point(px, py)));
            relpt = new Point(px, py);
            i += 1;
            cntrlpt = new Point(px + px-cntrlpt.x, py + py-cntrlpt.y);
          }else if(mode == 15){
            // this is followed by 2 numbers
            double x = relpt.x;
            double y = relpt.y;
            double px = x + Double.valueOf(pdata[i]).doubleValue();
            double py = y + Double.valueOf(pdata[i+1]).doubleValue();
            pathpoints.addAll(interpolateQuadratic(relpt, cntrlpt, new Point(px, py)));
            relpt = new Point(px, py);
            i += 1;
            cntrlpt = new Point(px + px-cntrlpt.x, py + py-cntrlpt.y);
          }else if(mode == 16){
            // this is followed by 7 numbers
            double rx = Double.valueOf(pdata[i]).doubleValue();
            double ry = Double.valueOf(pdata[i+1]).doubleValue();
            double xrot = Double.valueOf(pdata[i+2]).doubleValue();
            boolean bigarc = Integer.valueOf(pdata[i+3]) > 0;
            boolean sweep = Integer.valueOf(pdata[i+4]) > 0;
            double px = Double.valueOf(pdata[i+5]).doubleValue();
            double py = Double.valueOf(pdata[i+6]).doubleValue();
            pathpoints.addAll(interpolateArc(relpt, rx, ry, xrot, bigarc, sweep, new Point(px, py)));
            relpt = new Point(px, py);
            i += 6;
          }else if(mode == 17){
            // this is followed by 7 numbers
            double x = relpt.x;
            double y = relpt.y;
            double rx = Double.valueOf(pdata[i]).doubleValue();
            double ry = Double.valueOf(pdata[i+1]).doubleValue();
            double xrot = Double.valueOf(pdata[i+2]).doubleValue();
            boolean bigarc = Integer.valueOf(pdata[i+3]) > 0;
            boolean sweep = Integer.valueOf(pdata[i+4]) > 0;
            double px = x + Double.valueOf(pdata[i+5]).doubleValue();
            double py = y + Double.valueOf(pdata[i+6]).doubleValue();
            pathpoints.addAll(interpolateArc(relpt, rx, ry, xrot, bigarc, sweep, new Point(px, py)));
            relpt = new Point(px, py);
            i += 6;
          }else if(mode == 18){
            double tmpx = startpt.x;
            double tmpy = startpt.y;
            pathpoints.add(new Point(tmpx, tmpy));
            relpt = new Point(tmpx, tmpy);
          }else if(mode == 19){
            double tmpx = startpt.x;
            double tmpy = startpt.y;
            pathpoints.add(new Point(tmpx, tmpy));
            relpt = new Point(tmpx, tmpy);
          }
        } // end pdata loop
        
        // here we have completed this path. Yay!
        // read lines till we reach the true end of path "/>"
        while((lines[lind].indexOf("/>") < 0) && (lines[lind].indexOf("</path>") < 0)){
          // there could still be a transform in there!
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          lind++;
        }
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        
        // if there was a transform, apply it to the path
        if(hasTrans){
          // translate all points by this much
          pstring = lines[lind].substring(lines[lind].indexOf("translate(") + 10);
          pstring = pstring.substring(0, pstring.indexOf(")"));
          pdata = splitTokens(pstring, ", \t");
          double transx = Double.valueOf(pdata[0]).doubleValue();
          double transy = 0.0;
          Point tmppoint;
          if(pdata.length > 1){
            transy = Double.valueOf(pdata[1]).doubleValue();
          }
          for(int arrayind=0; arrayind<pathpoints.size(); arrayind++){
            tmppoint = pathpoints.get(arrayind);
            pathpoints.set(arrayind, new Point(tmppoint.x+transx, tmppoint.y+transy));
          }
        }
        
        // now add this path to the list
        allpoints.addAll(pathpoints);
        println("subpath complete, points: "+String.valueOf(pathpoints.size()));
        
        foundPath = false;
        
      } // end "<path" parsing
        
    } // end line searching
    
  } // end try block
  catch(Exception e) {
    e.printStackTrace();
  }
  
  // now all lines in the file have been processed
  
  println("total path points:"+allpoints.size());
  
  // rescale and translate the data
  // find max and min data
  minx = 1e10;
  maxx = -1e10;
  miny = 1e10;
  maxy = -1e10;
  float x, y, scl;
  for (int i=0; i<allpoints.size(); i++) {
    x = (float)allpoints.get(i).x;
    y = (float)allpoints.get(i).y;
    if(x > maxx){ maxx = x; }
    if(x < minx){ minx = x; }
    if(y > maxy){ maxy = y; }
    if(y < miny){ miny = y; }
  }
  if(maxy-miny > maxx-minx){
    scl = maxdim/(maxy-miny);
  }else{
    scl = maxdim/(maxx-minx);
  }
  for (int i=0; i<allpoints.size(); i++) {
    allpoints.get(i).x = scl*(allpoints.get(i).x - minx);
    allpoints.get(i).y = scl*(allpoints.get(i).y - miny);
  }
  
  // refind max and min 
  minx = 1e10;
  maxx = -1e10;
  miny = 1e10;
  maxy = -1e10;
  for (int i=0; i<allpoints.size(); i++) {
    x = (float)allpoints.get(i).x;
    y = (float)allpoints.get(i).y;
    if(x > maxx){ maxx = x; }
    if(x < minx){ minx = x; }
    if(y > maxy){ maxy = y; }
    if(y < miny){ miny = y; }
  }
  
  // if rotated, rotate the data
  if(rotated){
    double tmp;
    for (int i=0; i<allpoints.size(); i++) {
      tmp = allpoints.get(i).x;
      allpoints.get(i).x = maxy-allpoints.get(i).y;
      allpoints.get(i).y = tmp;
    }
    float tmp2 = maxx;
    maxx = maxy;
    maxy = tmp2;
    tmp2 = minx;
    minx = miny;
    miny = tmp2;
  }
  
  // now that all the points are found, write them to a file
  output = createWriter("disco.txt"); 
  output.print('{');
  for(int i=0; i<allpoints.size(); i++){
    output.print('{');
    output.print(allpoints.get(i).x);
    output.print(", ");
    output.print(allpoints.get(i).y);
    output.println("}, ");
  }
  output.println('}');
  
  output.print('{');
  for(int i=0; i<penMoves.size(); i++){
    output.print(penMoves.get(i));
    output.print(", ");
  }
  output.println('}');
  
  output.flush();
  output.close();
}

/*
* Interpolate the cubic Bezier curves (commands C,c,S,s)
*/
ArrayList<Point> interpolateCubic(Point p1, Point pc1, Point pc2, Point p2) {

  ArrayList<Point> pts = new ArrayList<Point>();

  pts.add(0, p1);
  pts.add(1, p2);
  double maxdist = Math.sqrt((p1.x-p2.x)*(p1.x-p2.x) + (p1.y-p2.y)*(p1.y-p2.y));
  double interval = 1.0;
  double win = 0.0;
  double iin = 1.0;
  int segments = 1;
  double tmpx, tmpy;

  while (maxdist > precision && segments < 1000) {
    interval = interval/2.0;
    segments = segments*2;

    for (int i=1; i<segments; i+=2) {
      win = 1-interval*i;
      iin = interval*i;
      tmpx = win*win*win*p1.x + 3*win*win*iin*pc1.x + 3*win*iin*iin*pc2.x + iin*iin*iin*p2.x;
      tmpy = win*win*win*p1.y + 3*win*win*iin*pc1.y + 3*win*iin*iin*pc2.y + iin*iin*iin*p2.y;
      pts.add(i, new Point(tmpx, tmpy));
    }
    if(segments > 3){
      maxdist = 0.0;
      for (int i=0; i<pts.size()-2; i++) {
        // this is the deviation from a straight line between 3 points
        tmpx = (pts.get(i).x-pts.get(i+1).x)*(pts.get(i).x-pts.get(i+1).x) + (pts.get(i).y-pts.get(i+1).y)*(pts.get(i).y-pts.get(i+1).y) - ((pts.get(i).x-pts.get(i+2).x)*(pts.get(i).x-pts.get(i+2).x) + (pts.get(i).y-pts.get(i+2).y)*(pts.get(i).y-pts.get(i+2).y))/4.0;
        if (tmpx > maxdist) {
          maxdist = tmpx;
        }
      }
      maxdist = Math.sqrt(maxdist);
    }
  }

  return pts;
}

/*
* Interpolate the quadratic Bezier curves (commands Q,q,T,t)
*/
ArrayList<Point> interpolateQuadratic(Point p1, Point pc1, Point p2) {

  ArrayList<Point> pts = new ArrayList<Point>();

  pts.add(0, p1);
  pts.add(1, p2);
  double maxdist = Math.sqrt((p1.x-p2.x)*(p1.x-p2.x) + (p1.y-p2.y)*(p1.y-p2.y));
  double interval = 1.0;
  double win = 0.0;
  double iin = 1.0;
  int segments = 1;
  double tmpx, tmpy;

  while (maxdist > precision && segments < 1000) {
    interval = interval/2.0;
    segments = segments*2;

    for (int i=1; i<segments; i+=2) {
      win = 1-interval*i;
      iin = interval*i;
      tmpx = win*win*p1.x + 2*win*iin*pc1.x + iin*iin*p2.x;
      tmpy = win*win*p1.y + 2*win*iin*pc1.y + iin*iin*p2.y;
      pts.add(i, new Point(tmpx, tmpy));
    }
    if(segments > 3){
      maxdist = 0.0;
      for (int i=0; i<pts.size()-2; i++) {
        // this is the deviation from a straight line between 3 points
        tmpx = (pts.get(i).x-pts.get(i+1).x)*(pts.get(i).x-pts.get(i+1).x) + (pts.get(i).y-pts.get(i+1).y)*(pts.get(i).y-pts.get(i+1).y) - ((pts.get(i).x-pts.get(i+2).x)*(pts.get(i).x-pts.get(i+2).x) + (pts.get(i).y-pts.get(i+2).y)*(pts.get(i).y-pts.get(i+2).y))/4.0;
        if (tmpx > maxdist) {
          maxdist = tmpx;
        }
      }
      maxdist = Math.sqrt(maxdist);
    }
  }

  return pts;
}

/*
* Interpolate the elliptical arcs (commands A,a)
*/
ArrayList<Point> interpolateArc(Point p1, double rx, double ry, double xrot, boolean bigarc, boolean sweep, Point p2) {

  ArrayList<Point> pts = new ArrayList<Point>();

  pts.add(0, p1);
  pts.add(1, p2);
  // if the ellipse is too small to draw
  if(Math.abs(rx) <= precision || Math.abs(ry) <= precision){
    return pts;
  }
  
  // Now we begin the task of converting the stupid SVG arc format 
  // into something actually useful (method derived from SVG specification)
  
  // convert xrot to radians
  xrot = xrot*PI/180.0;
  
  // radius check
  double x1 = Math.cos(xrot)*(p1.x-p2.x)/2.0 + Math.sin(xrot)*(p1.y-p2.y)/2.0;
  double y1 = -Math.sin(xrot)*(p1.x-p2.x)/2.0 + Math.cos(xrot)*(p1.y-p2.y)/2.0;
  
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  double rchk = x1*x1/rx/rx + y1*y1/ry/ry;
  if(rchk > 1.0){
    rx = Math.sqrt(rchk)*rx;
    ry = Math.sqrt(rchk)*ry;
  }
  
  // find the center
  double sq = (rx*rx*ry*ry - rx*rx*y1*y1 - ry*ry*x1*x1)/(rx*rx*y1*y1 + ry*ry*x1*x1);
  if(sq < 0){
    sq = 0;
  }
  sq = Math.sqrt(sq);
  double cx1 = 0.0;
  double cy1 = 0.0;
  if(bigarc==sweep){
    cx1 = -sq*rx*y1/ry;
    cy1 = sq*ry*x1/rx;
  }else{
    cx1 = sq*rx*y1/ry;
    cy1 = -sq*ry*x1/rx;
  }
  double cx = (p1.x+p2.x)/2.0 + Math.cos(xrot)*cx1 - Math.sin(xrot)*cy1;
  double cy = (p1.y+p2.y)/2.0 + Math.sin(xrot)*cx1 + Math.cos(xrot)*cy1;
  
  // find angle start and angle extent
  double theta = 0.0;
  double dtheta = 0.0;
  double ux = (x1-cx1)/rx;
  double uy = (y1-cy1)/ry;
  double vx = (-x1-cx1)/rx;
  double vy = (-y1-cy1)/ry;
  double thing = Math.sqrt(ux*ux + uy*uy);
  double thing2 = thing * Math.sqrt(vx*vx + vy*vy);
  if(thing == 0){
    thing = 1e-7;
  }
  if(thing2 == 0){
    thing2 = 1e-7;
  }
  if(uy < 0){
    theta = -Math.acos(ux/thing);
  }else{
    theta = Math.acos(ux/thing);
  }
  
  if(ux*vy-uy*vx < 0){
    dtheta = -Math.acos((ux*vx+uy*vy)/thing2);
  }else{
    dtheta = Math.acos((ux*vx+uy*vy)/thing2);
  }
  dtheta = dtheta%(2*PI);
  if(sweep && dtheta < 0){
    dtheta += 2*PI;
  }
  if(!sweep && dtheta > 0){
    dtheta -= 2*PI;
  }
  
  // Now we have converted from stupid SVG arcs to something useful.
  
  double maxdist = 100;
  double interval = dtheta;
  int segments = 1;
  double tmpx, tmpy;

  while (maxdist > precision && segments < 1000) {
    interval = interval/2.0;
    segments = segments*2;

    for (int i=1; i<=segments; i+=2) {
      tmpx = cx + rx*Math.cos(theta+interval*i)*Math.cos(xrot) - ry*Math.sin(theta+interval*i)*Math.sin(xrot);
      tmpy = cy + rx*Math.cos(theta+interval*i)*Math.sin(xrot) + ry*Math.sin(theta+interval*i)*Math.cos(xrot);
      pts.add(i, new Point(tmpx, tmpy));
    }

    if(segments > 3){
      maxdist = 0.0;
      for (int i=0; i<pts.size()-2; i++) {
        // this is the deviation from a straight line between 3 points
        tmpx = (pts.get(i).x-pts.get(i+1).x)*(pts.get(i).x-pts.get(i+1).x) + (pts.get(i).y-pts.get(i+1).y)*(pts.get(i).y-pts.get(i+1).y) - ((pts.get(i).x-pts.get(i+2).x)*(pts.get(i).x-pts.get(i+2).x) + (pts.get(i).y-pts.get(i+2).y)*(pts.get(i).y-pts.get(i+2).y))/4.0;
        if (tmpx > maxdist) {
          maxdist = tmpx;
        }
      }
      maxdist = Math.sqrt(maxdist);
    }
  }

  return pts;
}

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

/*
* IMPORTANT: This is the way the data is sent
*  'S' signals the beginning of transmission
*  'U' signals a raise
*  'D' signals a lower
*  numbers are sent multiplied by 10000 and truncated to int 
*  numbers are sent as strings, one character at a time
*  '.' signals the end of a number
*  'F' signals the end of the transmission
*/
void sendData() {
  // connect 
  connectToArduino();
  if(sPort == null){
    // failed to connect, do nothing
    return;
  }
  
  // Then send the data 
  //String xdat, ydat;
  // clear the port
  while (sPort.available () > 0) {
    sPort.read();
  }
  // signal to begin 
  sPort.write('S');
  // send each point
  for(int i=0; i<allpoints.size(); i++){
    // if there is a z change, do that first
    for(int j=0; j<penMoves.size(); j++){
      if ((penMoves.get(j) == i || penMoves.get(j) == -i) && i > 0) {
        if (penMoves.get(j) == i) {
          sPort.write('U'); // this moves the pen up
        }
        else {
          sPort.write('D'); // this moves the pen down
        }
        int timeLimit = 0;
        while (sPort.available () < 1) {
          delay(10);
          timeLimit++;
          if (timeLimit > 60000) {
            println("timed out");
            return;
          }
        }
        sPort.read();
        penDown = !penDown;
        println("switched Z: "+penDown);
        break;
      }
    }
    // send a string of x data, wait for reply
    sendNumber((int)(allpoints.get(i).x*10000));
    
    // send a string of y data, wait for reply
    sendNumber((int)(allpoints.get(i).y*10000));

    println("sent N:"+i+" X:"+String.valueOf((int)(allpoints.get(i).x*10000))+" Y:"+String.valueOf((int)(allpoints.get(i).y*10000)));
  }
  
  // now we have sent all of the data. Yay!
  // signal to end 
  sPort.write('F');
  
  println("Sending complete");
}

void connectToArduino(){
  if(sPort==null){
    sPort = new Serial(this, serialPort, 115200);
    if(sPort==null){
      println("couldn't find serial port");
      return;
    }else{
      // delay in case the arduino reset 
      delay(1000);
    }
  }else{
    // previously connected
    return;
  }
  
  int timeLimit = 0;
  while (sPort.available () < 1) {
    sPort.write('#');
    delay(10);
    timeLimit++;
    if (timeLimit > 3000) {
      println("timed out");
      return;
    }
  }
  int check = sPort.read();
  if(check == '@'){
    println("Arduino connected");
  }else if(check == '!'){
    println("connected, but strange");
  }else{
    println("connected, but with error");
  }
}

void sendNumber(int num){
  String numstring = String.valueOf(num);
  for (int j=0; j<numstring.length(); j++) {
    sPort.write(numstring.charAt(j));
  }
  sPort.write('.');
  int timeLimit = 0;
  while (sPort.available () < 1) {
    delay(10);
    timeLimit++;
    if (timeLimit > 60000) {
      println("timed out");
      return;
    }
  }
  //char check = sPort.read();
  while (sPort.available () > 0) {
    sPort.read();
  }
}

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

/*
* This draws a picture from the list of coordinates
*/
void makePicture() {
  color blk = color(0);
  color wht = color(255);
  background(wht);
  if(allpoints.size() < 2){
    return;
  }
  stroke(blk);
  strokeWeight(1);
  int x0 = 50;
  int y0 = 50;
  int xn = 0;
  int yn = 0;
  float scl = 1.0; // pixels per mm
  float tmpx = 0.0;
  float tmpy = 0.0;
  penDown = true;
  
  // max and min data should be ready
  if(maxy-miny > maxx-minx){
    scl = (float)(height*1.0/(maxy-miny));
  }else{
    scl = (float)(width*1.0/(maxx-minx));
  }
  
  x0 = (int)(minx*scl);
  y0 = (int)(miny*scl);
  
  for (int i=0; i<allpoints.size(); i++) {
    for (int j=0; j<penMoves.size(); j++) {
      if (penMoves.get(j) == i) {
        penDown = false;
      }
      if (penMoves.get(j) == -i && i > 0) {
        penDown = true;
      }
    }
    tmpx = (float)allpoints.get(i).x;
    tmpy = (float)allpoints.get(i).y;
    if (penDown) {
      line(xn-x0, (yn-y0), int(tmpx*scl)-x0, (int(tmpy*scl)-y0));
    }
    xn = int(tmpx*scl);
    yn = int(tmpy*scl);
  }
  
}

// let's try shading using hatches
void makeHatches(float interval, float slope, int threshold){
  // start at the top left and move down then right
  float hx = 0;
  float hy = 0;
  int x, y;
  int maxPix = pixWidth;
  if(pixHeight > pixWidth){
    maxPix = pixHeight;
  }
  float scl = maxdim/maxPix;
  float xInterval;
  if(slope > 1 || slope < -1){
    xInterval = interval;
    interval = abs(xInterval*slope);
  }else{
    xInterval = abs(interval/slope);
  }
  boolean hatchStarted = false;
  float startX = 0;
  float startY = 0;
  float endX = 0;
  float endY = 0;
  
  int hatchCount = 0;
  
  // first move down along the left side
  while(hy < pixHeight){
    x = 0;
    y = int(hy);
    while((x < pixWidth) && (y >= 0) && (y < pixHeight)){
      if(((pixels[y*width + x] & 0xFF) < threshold) && !hatchStarted){
        hatchStarted = true;
        // find start point
        startX = x*scl;
        startY = y*scl;
      }else if(((pixels[y*width + x] & 0xFF) >= threshold) && hatchStarted){
        hatchStarted = false;
        // find end point
        endX = (x-1)*scl;
        endY = (y+1)*scl;
        if(slope > 0){
          endY = (y-1)*scl;
        }
        // if the line is longer than min length, add the points to the list
        if(abs(endX-startX) + abs(endY-startY) > minHatchLength){
          // lift and lower pen
          penMoves.add(allpoints.size());
          penMoves.add(-allpoints.size()-1);
          // add start and end points
          allpoints.add(new Point((double)startX, (double)startY));
          allpoints.add(new Point((double)endX, (double)endY));
          hatchCount++;
        }
      }
      
      x++;
      y = int(hy + x*slope);
    }
    if(hatchStarted){
      // it probably ran into the edge of the picture so end it
      hatchStarted = false;
      // lift and lower pen
      penMoves.add(allpoints.size());
      penMoves.add(-allpoints.size()-1);
      // add start and end points
      allpoints.add(new Point((double)startX, (double)startY));
      allpoints.add(new Point((double)(x-1)*scl, (double)(hy+(x-1)*slope)*scl));
      hatchCount++;
    }
    
    hy += interval*maxPix;
  }
  // if the slope is negative(slants up to the right) move right across the bottom
  // if the slope is positive, move across the top
  if(slope < 0){
    // then move right across the bottom
    hx = (pixHeight-hy)*1.0/slope;
    hy = pixHeight-1;
    while(hx < pixWidth){
      x = int(hx);
      if(x < 0){
        x = 0;
      }
      y = pixHeight-1;
      while((x < pixWidth) && (y >= 0) && (y < pixHeight)){
        if(((pixels[y*width + x] & 0xFF) < threshold) && !hatchStarted){
          hatchStarted = true;
          // find start point
          startX = x*scl;
          startY = y*scl;
        }else if(((pixels[y*width + x] & 0xFF) >= threshold) && hatchStarted){
          hatchStarted = false;
          // find end point
          endX = (x-1)*scl;
          endY = (y+1)*scl;
          // if the line is longer than min length, add the points to the list
          if(abs(endX-startX) + abs(endY-startY) > minHatchLength){
            // lift and lower pen
            penMoves.add(allpoints.size());
            penMoves.add(-allpoints.size()-1);
            // add start and end points
            allpoints.add(new Point((double)startX, (double)startY));
            allpoints.add(new Point((double)endX, (double)endY));
            hatchCount++;
          }
        }
        x++;
        y = int((pixHeight-1) + (x-hx)*slope);
      }
      if(hatchStarted){
        // it probably ran into the edge of the picture so end it
        hatchStarted = false;
        // lift and lower pen
        penMoves.add(allpoints.size());
        penMoves.add(-allpoints.size()-1);
        // add start and end points
        allpoints.add(new Point((double)startX, (double)startY));
        allpoints.add(new Point((double)(x-1)*scl, (double)(pixHeight-1+(x-hx-1)*slope)*scl));
        hatchCount++;
      }
      
      hx += xInterval*maxPix;
    }
  }
  if(slope > 0){
    // then move right across the top
    hx = int(interval*maxPix*1.0/slope);
    hy = 0;
    while(hx < pixWidth){
      x = int(hx);
      y = 0;
      while((x < pixWidth) && (y >= 0) && (y < pixHeight)){
        if(((pixels[y*width + x] & 0xFF) < threshold) && !hatchStarted){
          hatchStarted = true;
          // find start point
          startX = x*scl;
          startY = y*scl;
        }else if(((pixels[y*width + x] & 0xFF) >= threshold) && hatchStarted){
          hatchStarted = false;
          // find end point
          endX = (x-1)*scl;
          endY = (y-1)*scl;
          // if the line is longer than min length, add the points to the list
          if(abs(endX-startX) + abs(endY-startY) > minHatchLength){
            // lift and lower pen
            penMoves.add(allpoints.size());
            penMoves.add(-allpoints.size()-1);
            // add start and end points
            allpoints.add(new Point((double)startX, (double)startY));
            allpoints.add(new Point((double)endX, (double)endY));
            hatchCount++;
          }
        }
        x++;
        y = int((x-hx)*slope);
      }
      if(hatchStarted){
        // it probably ran into the edge of the picture so end it
        hatchStarted = false;
        // lift and lower pen
        penMoves.add(allpoints.size());
        penMoves.add(-allpoints.size()-1);
        // add start and end points
        allpoints.add(new Point((double)startX, (double)startY));
        allpoints.add(new Point((double)(x-1)*scl, (double)((x-hx-1)*slope)*scl));
        hatchCount++;
      }
      
      hx += xInterval*maxPix;
    }
  }
  
  print(hatchCount);
  println( " hatches");
}

// a convenience class for storing 2-D double coordinates
class Point {
  public double x;
  public double y;
  Point(double nx, double ny) {
    x = nx;
    y = ny;
  }
}