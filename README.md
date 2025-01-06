# Updater

A basic script for updating several linux based distributions.

## Features

* Sync and update package cache
* Updated installed packages to their latest versions
* Create a ZFS snapshot before and after updating the system

> The ZFS snapshot feature is experimental and enabled only for __Arch Linux__.
>
> This feature is provided by `zfs-snap-mgr` from the [CachyOS ZFS Tools](https://github.com/Jiab77/cachyos-zfs-tools) project.

## Distributions

Here is a list of supported distributions:

* Debian / Ubuntu / Pop!_OS / ElementaryOS
* RedHat / CentOS / Fedora / Rocky Linux
* Arch Linux / CachyOS
* Termux

Please, feel free to create a new issue for requesting support for additional distributions.

## Usage

```console
$ ./updater.sh
```

<!--
> Depending on your OS, you may have to run the script with `sudo`.
-->

## Author

* __Jiab77__
