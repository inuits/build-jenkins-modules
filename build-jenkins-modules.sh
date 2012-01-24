#!/bin/bash

## These values should not be changed, but can be if needed.
JENKINS_PLUGINS_MIRROR="${JENKINS_PLUGINS_MIRROR-https://updates.jenkins-ci.org}"
JENKINS_DIR="${JENKINS_DIR-/var/lib/jenkins}"
JENKINS_PLUGIN_DIR="${JENKINS_PLUGIN_DIR-${JENKINS_DIR}/plugins}"

function package_plugin() {
  local name="$1";
  local version="$2";
  local dependencies="$3";
  local build_dir="BUILD/${name}";
  local plugin_file="${build_dir}/${name}.hpi";
  local plugin_dir="${build_dir}/${name}/";
  local manifest_file="BUILD/${name}.manifest";
  local plugin_url plugin_deps plugin_desc plugin_hudson;
  local depname depversion;

  echo "Preparing build environment for: ${name}"
  if [ -d "BUILD/${name}" ]; then
     rm -rf "BUILD/${name}";
  fi
  mkdir -p "$build_dir/${name}";
  cat > "BUILD/rpm-postinstall-${name}.sh" << EOM
chown -R jenkins:jenkins /var/lib/jenkins/plugins/${name} /var/lib/jenkins/plugins/${name}.hpi
chown jenkins:jenkins /var/lib/jenkins/plugins
EOM

  if [ x"$version" == 'x' ]; then
    echo "Fetching ${name}/latest from jenkins mirror";
    plugin_url="${JENKINS_PLUGINS_MIRROR}/latest/${name}.hpi"
  else
    echo "Fetching ${name}/${version} from jenkins mirror";
    plugin_url="${JENKINS_PLUGINS_MIRROR}/download/plugins/${name}/${version}/${name}.hpi"
  fi
  wget -q --no-check-certificate "$plugin_url" -O "$plugin_file" || return 1;

  get_plugin_manifest_from_hpi "$plugin_file" "$manifest_file" || ( echo 'Plugin file not found!' 1>&2  && return 1; )

  version="$( grep 'Plugin-Version:' < $manifest_file |cut -d ' ' -f 2 )";
  plugin_deps="$( grep 'Plugin-Dependencies:' < $manifest_file | cut -d ' ' -f 2 )";
  plugin_desc="$( grep 'Long-Name:' < $manifest_file | cut -d ' ' -f 2- )";
  plugin_hudson="$( grep 'Hudson-Version:' < $manifest_file | cut -d ' ' -f 2 | grep -o '[0-9]\+\.[0-9]\+' )";
  plugin_url="$( grep 'Url:' < $manifest_file | cut -d ' ' -f 2- )";

  echo 'FPM packaging starts here!'
  echo "+ Plugin name: ${name}"
  echo "+ Version: ${version}"
  echo "+ Required jenkins version: ${plugin_hudson}"
  local fpm_cmd="fpm -n jenkins-plugin-${name} -v ${version} -s dir -t rpm";
  fpm_cmd="${fpm_cmd} --prefix ${JENKINS_PLUGIN_DIR} -C ${build_dir} -a noarch";
  fpm_cmd="${fpm_cmd} --description \"${plugin_desc}\" --url \"${plugin_url}\"";
  fpm_cmd="${fpm_cmd} --post-install BUILD/rpm-postinstall-${name}.sh";
  if [ -n $plugin_hudson ]; then
    fpm_cmd="${fpm_cmd} -d 'jenkins'";
  else
    fpm_cmd="${fpm_cmd} -d 'jenkins >= ${plugin_hudson}'";
  fi;


  local oldifs="${IFS}"; IFS=',';
  for dep in $dependencies; do
    fpm_cmd="${fpm_cmd} -d '${dep}'";
  done;
  for dep in $plugin_deps; do
      if echo $dep | grep -q -v '=optional'; then
        depname="$( echo $dep | cut -d ':' -f 1 )";
        depversion="$( echo $dep | cut -d ':' -f 2 )" ;
        fpm_cmd="${fpm_cmd} -d 'jenkins-plugin-${depname} >= ${depversion}'"
        echo "++ Dependency found: $dep";
      else
        echo "-- Optional dependency found: $dep";
      fi;
  done;
  IFS="${oldifs}";
  fpm_cmd="${fpm_cmd} "
  eval $fpm_cmd 
  retval=$?
  echo "Build of ${name} finished with return status: $retval";
  return $retval;
}

get_plugin_manifest_from_hpi() {
  local pluginfile=$1;
  local target=$2;
  if [ -f "$pluginfile" ]; then
    unzip -p $pluginfile META-INF/MANIFEST.MF | tr -d '\r' | sed -e ':a;N;$!ba;s/\n //g' > $target
    return 0;
  else
    return 1;
  fi;
}

## Create build folder.
mkdir -p BUILD
for plugin in $(grep -v '#' < jenkins-plugins)
do
    name=$(echo $plugin | awk -F : '{print $1}')
    version=$(echo $plugin | awk -F : '{print $2}')
    dependencies=$(echo $plugin | awk -F : '{print $3}')
    package_plugin "$name" "$version" "$dependencies" || exit 1;
done

echo "PWD: `pwd`"

if [ -d ARTIFACTS ]
then
    rm -rf ARTIFACTS
fi
mkdir ARTIFACTS
mv -v *.rpm ARTIFACTS/
rm -rf BUILD
