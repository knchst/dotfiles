#! /bin/sh

# install HomeBrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew tap Homebrew/bundle
brew bundle

# Xcode color scheme
mkdir ~/Library/Developer/Xcode/UserData/FontAndColorThemes/
cp wwdc17.xccolortheme ~/Library/Developer/Xcode/UserData/FontAndColorThemes/

# install dotfiles
./install_dotfiles.sh
