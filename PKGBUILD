# Maintainer: Chrysostomus @forum.manjaro.org
# Maintainer: Bernhard Landauer <oberon@manjaro.org>

pkgbase=manjaro-architect
pkgname=('manjaro-architect' 'manjaro-architect-launcher')
pkgver=0.9.19
pkgrel=4
pkgdesc="Manjaro CLI net-installer, forked from the Archlinux Architect"
arch=(any)
url="https://github.com/GrayWolf82/$pkgbase"
license=(GPL2)
depends=('bash'
         'dialog')
makedepends=('git')
optdepends=('maia-console'
            'terminus-font')
source=("git+$url.git#branch=master")
md5sums=('SKIP')

pkgver() {
    cd $pkgbase
    git describe --long --tags | sed 's/\([^-]*-g\)/r\1/;s/-/./g'
}

build() {
    cd $pkgbase
	make PREFIX=/usr
}

package_manjaro-architect() {
    depends+=('f2fs-tools'
         'gptfdisk'
         'manjaro-architect-launcher'
         'manjaro-tools-base'
         'mhwd'
         'nilfs-utils'
         'pacman-mirrorlist'
         'parted')
    cd $pkgbase
	make PREFIX=/usr DESTDIR=${pkgdir} install
}

package_manjaro-architect-launcher() {
    cd $pkgbase
    install -Dm755 bin/setup $pkgdir/usr/bin/setup
}
