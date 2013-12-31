#!/bin/bash

PATH="/var/lib/gems/1.8/bin:$PATH"

## These values should not be changed, but can be if needed.
JENKINS_PLUGINS_MIRROR="${JENKINS_PLUGINS_MIRROR-https://updates.jenkins-ci.org}"
JENKINS_DIR="${JENKINS_DIR-/var/lib/jenkins}"
JENKINS_PLUGIN_DIR="${JENKINS_PLUGIN_DIR-${JENKINS_DIR}/plugins}"

OLDPS4="${PS4}"
function prefix() {
  local count=$1;
  local nr=$2;
  local len=`echo $count | wc -c`;
  printf "[%${len}d/%d]" $nr $count;
}

function package_plugin() {
  local name="$1";
  local version="$2";
  local dependencies="$3";
  local count=$4;
  local nr=$5;
  local dist=$6;

  local prefix=`prefix $count $nr`;
  local build_dir="BUILD/${name}";
  local plugin_file="${build_dir}/${name}.hpi";
  local plugin_dir="${build_dir}/${name}/";
  local manifest_file="BUILD/${name}.manifest";
  local plugin_url plugin_deps plugin_desc plugin_hudson;
  local depname depversion;

  case "$dist" in
    deb)
      arch="all"
      user="jenkins"
      group="nogroup"
      ;;
    rpm)
      arch="noarch"
      user="jenkins"
      group="jenkins"
      ;;
    *)
      echo "Operatinsystem ${dist} is not supported." && exit 255
  esac

  echo "${prefix} Preparing build environment for: ${name}"
  if [ -d "BUILD/${name}" ]; then
     rm -rf "BUILD/${name}";
  fi
  mkdir -p "$build_dir/${name}";
  cat > "BUILD/${dist}-postinstall-${name}.sh" << EOM
#!/bin/sh
chown -R ${user}:${group} /var/lib/jenkins/plugins
EOM

  if [ -f "manual/${name}.hpi" ]; then
    cp -rv "manual/${name}.hpi" $plugin_file;
  else
    if [[ x"$version" == 'x' || x"$version" == 'x-' ]]; then
      echo "${prefix} Fetching ${name}/latest from jenkins mirror";
      plugin_url="${JENKINS_PLUGINS_MIRROR}/latest/${name}.hpi"
    else
      echo "${prefix} Fetching ${name}/${version} from jenkins mirror";
      plugin_url="${JENKINS_PLUGINS_MIRROR}/download/plugins/${name}/${version}/${name}.hpi"
    fi
    wget -nv --no-check-certificate "$plugin_url" -O "$plugin_file" || return 1;
  fi;

  get_plugin_manifest_from_hpi "$plugin_file" "$manifest_file" || ( echo "Plugin file not found: '${$plugin_file}'!" 1>&2  && return 1; )

  version="$( grep 'Plugin-Version:' < $manifest_file |cut -d ' ' -f 2 )";
  plugin_deps="$( grep 'Plugin-Dependencies:' < $manifest_file | cut -d ' ' -f 2 )";
  plugin_desc="$( grep 'Long-Name:' < $manifest_file | cut -d ' ' -f 2- )";
  plugin_hudson="$( grep 'Hudson-Version:' < $manifest_file | cut -d ' ' -f 2 | grep -o '[0-9]\+\.[0-9]\+' )";
  plugin_url="$( grep 'Url:' < $manifest_file | cut -d ' ' -f 2- )";

  echo "${prefix} FPM packaging starts here!"
  echo "${prefix} + Plugin name: ${name}"
  echo "${prefix} + Version: ${version}"
  echo "${prefix} + Required jenkins version: ${plugin_hudson}"
  local fpm_cmd="fpm -n jenkins-plugin-${name} -v ${version} -s dir -t ${dist} --epoch=1";
  fpm_cmd="${fpm_cmd} --prefix ${JENKINS_PLUGIN_DIR} -C ${build_dir} -a ${arch}";
  fpm_cmd="${fpm_cmd} --description \"${plugin_desc}\" --url \"${plugin_url}\"";
  fpm_cmd="${fpm_cmd} --after-install BUILD/${dist}-postinstall-${name}.sh";
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
        echo "${prefix} ++ Dependency found: $dep";
      else
        echo "${prefix} -- Optional dependency found: $dep";
      fi;
  done;
  IFS="${oldifs}";
  fpm_cmd="${fpm_cmd} ${name}.hpi"
  eval $fpm_cmd
  retval=$?
  echo "${prefix} Build of ${name} finished with return status: $retval";
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

get_all_plugins_from_update_center() {
  wget --no-check-certificate -q "${JENKINS_PLUGINS_MIRROR}/update-center.json" -O - | grep -o "plugins/[^/]*"  | sed -e "s@^plugins/@@g"
}

package_all() {
  local count=$#;
  local nr=0;
  local extras name version dependencies;
  for plugin in $*;
  do
    let nr++;
    extras=$( grep "^${plugin}\(:.*\)\?\$" jenkins-plugins-rpm );
    #name=$(echo $plugin | awk -F : '{print $1}')
    name=$plugin;
    version=$(echo $extras | awk -F : '{print $2}')
    dependencies=$(echo $extras | awk -F : '{print $3}')
    package_plugin "$name" "$version" "$dependencies" "$count" "$nr" rpm || echo $plugin >> faillist.txt
    package_plugin "$name" "$version" "$dependencies" "$count" "$nr" deb || echo $plugin >> faillist.txt
  done
}

## Create build folder.
mkdir -p BUILD
if [ -f faillist.txt ]
then
  rm faillist.txt
fi


#for plugin in $(grep -v '#' < jenkins-plugins)
if [ -z $1 ]; then
  package_all $( get_all_plugins_from_update_center )
else
  package_all $*
fi

export PS4="${OLDPS4}"

if [ -d ARTIFACTS ]
then
    rm -rf ARTIFACTS
fi
mkdir ARTIFACTS
mv -v *.rpm ARTIFACTS/
mv -v *.deb ARTIFACTS/
rm -rf BUILD
