## Introduction

This script will create RPM files for each jenkins plugin defined in the jenkins-plugins file.

## Description

The RPMs are generated with the help of [fpm](https://github.com/jordansissel/fpm).
Each plugin rpm depends on jenkins. If a specific version is set in the manifest file, the
dependency on jenkins is added as 'jenkins >= VERSION'.

Other plugin Dependencies found in the manifest file are also added as rpm deps too.

## Sources

The script will attempt to get the hpi file from the jenkins updates server.
In cases that this does not work, create a folder 'manual' and place the {name}.hpi file
in there, the script will then use that file in stead of attempting to wget it.

## jenkins-plugins-rpm File Format

Each line defined a plugin to build using the script. Arguments on each line are separated by a colon (:).

* The first argument is mandatory and is the plugin name.
* The second argument defines a specific version to be build and is optional. If left empty, the latest version will be installed.
* The third argument defines additional rpm dependencies. Add them as you would in a rpm spec file and seperate them with a comma (,).

The resulting rpm filename will be jenkins-plugin-PLUGINNAME-version-....

## RPM Installation

You can either add the rpms to your local repository or install them manually.

Note: You will have to restart jenkins after installing a rpm to make the new plugins working.
