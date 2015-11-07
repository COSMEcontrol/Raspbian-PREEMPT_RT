#!/bin/bash
#####################################################
#### Alberto Azuara
#### Shoghi Cervantes
#### Versión 1.0
#### 04/11/14
#### Update RT-Preempt
#####################################################

basedir=`pwd`

function update {
    cd "$basedir/$1"
    git fetch && git reset --hard origin/$2
    cd ../
    git add $1
}

update Raspbian $1
