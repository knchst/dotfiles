#! /bin/sh

# install HomeBrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew tap Homebrew/bundle
brew bundle

cp wwdc17.xccolortheme ~/Library/Developer/Xcode/UserData/FontAndColorThemes/

git clone https://github.com/flutter/flutter.git -b stable && mv ./flutter /usr/local/bin
rm -rf ./flutter

# Vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

# rbenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build

./install_dotfile.sh