#!/bin/bash

# Install necessary software
sudo apt update
sudo apt-get install -y python3-pip python-dev python3-dev r-cran-rjava openjdk-8-jre r-base sqlite3 libsqlite3-dev sqlcipher libsqlcipher-dev git

# Install python packages
## the following command produces a warning message which can be safely ignored:
pip3 install --upgrade pip --user
## warning message:
## "You are using pip version 8.1.1, however version 10.0.1 is available.
## You should consider upgrading via the 'pip install --upgrade pip' command."
hash -d pip3
## However, running the above command and then "pip3 --version" shows that version 10.0.1 is indeed installed.
pip3 install --upgrade setuptools --user
pip3 install requests pysqlcipher3 pandas --user

# Write an R script to install packages, then run and remove script
echo "install.packages(c('openVA', 'CrossVA'), dependencies=TRUE, repos='https://cran.case.edu/')
q('no')" > packages.r

sudo Rscript packages.r
rm packages.r

# Download ODK Briefcase v1.10.1
wget -nd https://github.com/opendatakit/briefcase/releases/download/v1.10.1/ODK-Briefcase-v1.10.1.jar

# optional (but recommended) step for installing DB Browser for SQLite (useful for configuring pipeline)
sudo apt install -y build-essential git cmake libsqlite3-dev qt5-default qttools5-dev-tools
git clone https://github.com/sqlitebrowser/sqlitebrowser

cd sqlitebrowser
mkdir build
cd build
cmake -Dsqlcipher=1 -Wno-dev ..
make
sudo make install
