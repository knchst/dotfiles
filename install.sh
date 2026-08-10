#! /bin/sh

# install HomeBrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew tap Homebrew/bundle
brew bundle

# install mise
curl -fsSL https://mise.run | sh

# install agent-slack
curl -fsSL https://raw.githubusercontent.com/stablyai/agent-slack/main/install.sh | sh

# Xcode color scheme
mkdir ~/Library/Developer/Xcode/UserData/FontAndColorThemes/
cp wwdc17.xccolortheme ~/Library/Developer/Xcode/UserData/FontAndColorThemes/

# install dotfiles
./install_dotfiles.sh
