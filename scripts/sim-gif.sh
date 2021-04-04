xcrun simctl io booted recordVideo ~/Documents/simulator.mov
ffmpeg -i ~/Documents/simulator.mov -r 10 -y ~/Documents/simulator.gif
rm ~/Documents/simulator.mov
open ~/Documents