#!/bin/bash
mkdir -p BUILD
PLUGINS_MIRROR="http://updates.jenkins-ci.org/"
FPM="/usr/lib/ruby/gems/1.8/bin/fpm"

for plugin in $(grep -v '#' < jenkins-plugins)
do
    name=$(echo $plugin | awk -F : '{print $1}')
    version=$(echo $plugin | awk -F : '{print $2}')
    echo "Building $name"
    if [ -d "BUILD/${name}" ]
    then
        rm -rf "BUILD/${name}"
    fi
    mkdir -p "BUILD/${name}/${name}"
    if [ x$version == 'x' ]; then
        LINK="${PLUGINS_MIRROR}/latest/${name}.hpi"
    else
        echo "Building $name version $version"
        LINK="${PLUGINS_MIRROR}/download/plugins/${name}/${version}/${name}.hpi"
    fi
    wget --no-check-certificate "$LINK" -O "BUILD/${name}/${name}.hpi"
    cd BUILD/${name}/${name}
    unzip ../${name}.hpi
    if [ x$version == 'x' ]; then
        version="$(grep Plugin-Version: < META-INF/MANIFEST.MF|cut -d ' ' -f 2|tr -d "\r")"
    fi
    cd ../..
    $FPM -n "jenkins-plugin-${name}" -v "$version" -s dir -t rpm \
        --prefix /var/lib/jenkins/plugins/ -C "${name}" \
        -a noarch --description "Jenkins plugin ${name}" \
        --url "${PLUGINS_MIRROR}/download/plugins/${name}"
    RETVAL="$?"
    cd ..
    echo "Build of $name returned with $RETVAL"
    [ $RETVAL -ne 0 ] && exit $RETVAL
done
if [ -d ARTIFACTS ]
then
    rm -rf ARTIFACTS
fi
mkdir ARTIFACTS
mv BUILD/*.rpm ARTIFACTS
rm -rf BUILD
