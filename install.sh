#! /bin/sh

TARGET=$HOME
IGNOREFILES=('..', '.hgrc' '.DS_Store', '.gitignore')

for dotfile in .?* ; do
    
  if `echo ${IGNOREFILES[@]} | grep -q "$dotfile"` ; then
    echo "😌 Ignored ${dotfile}"
    continue
  fi
  
  if [[ -f $dotfile ]]; then
    ln -sf $PWD/$dotfile $TARGET
    suffix="@"
  elif [[ -d $dotfile ]]; then
    ln -sf $PWD/$dotfile $TARGET/
    suffix="/"
  fi
  echo "😎 Created $1/$dotfile$suffix"
done

mv wwdc17.xccolortheme ~/Library/Developer/Xcode/UserData/FontAndColorThemes/

git clone https://github.com/flutter/flutter.git -b stable && mv ./flutter /usr/local/bin
