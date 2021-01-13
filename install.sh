#! /bin/sh

# install HomeBrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew tap Homebrew/bundle
brew bundle

cp wwdc17.xccolortheme ~/Library/Developer/Xcode/UserData/FontAndColorThemes/

git clone https://github.com/flutter/flutter.git -b stable && mv ./flutter /usr/local/bin
rm -rf ./flutter

git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
git clone https://github.com/rbenv/rbenv.git ~/.rbenv

./install_dotfile.sh