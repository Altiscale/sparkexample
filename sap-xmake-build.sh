#!/bin/bash -l

# This build script is only applicable to Spark without Hadoop and Hive

curr_dir=`dirname $0`
curr_dir=`cd $curr_dir; pwd`
git_hash=""

export M2_HOME=/opt/mvn3.6.3
cp -f /maven/settings.xml ${M2_HOME}/conf/
export JAVA_HOME=/opt/java

# AE-1226 temp fix on the R PATH
export R_HOME=/usr
if [ "x${R_HOME}" = "x" ] ; then
  echo "warn - R_HOME not defined, CRAN R isn't installed properly in the current env"
else
  echo "ok - R_HOME redefined to $R_HOME based on installed RPM due to AE-1226"
fi

export PATH=$M2_HOME/bin:$JAVA_HOME/bin:$PATH:$R_HOME

export HADOOP_VERSION=${HADOOP_VERSION:-"2.7.7"}
export HIVE_VERSION=${HIVE_VERSION:-"2.3.3"}
# Define default spark uid:gid and build version
# and all other Spark build related env
export SPARK_PKG_NAME=${SPARK_PKG_NAME:-"spark"}
export SPARK_GID=${SPARK_GID:-"411460017"}
export SPARK_UID=${SPARK_UID:-"411460024"}
export SPARK_VERSION=${SPARK_VERSION:-"3.0.0"}
export SCALA_VERSION=${SCALA_VERSION:-"2.12"}

if [[ $SPARK_VERSION == 2.* ]] ; then
  if [[ $SCALA_VERSION != 2.12 ]] ; then
    2>&1 echo "error - scala version requires 2.12+ for Spark $SPARK_VERSION, can't continue building, exiting!"
    exit -1
  fi
fi

export BUILD_TIMEOUT=${BUILD_TIMEOUT:-"86400"}
# centos6.5-x86_64
# centos6.6-x86_64
# centos6.7-x86_64
export BUILD_ROOT=${BUILD_ROOT:-"centos6.5-x86_64"}
export BUILD_TIME=$(date +%Y%m%d%H%M)
# Customize build OPTS for MVN
export MAVEN_OPTS=${MAVEN_OPTS:-"-Xmx2048m -XX:MaxPermSize=1024m"}
export PRODUCTION_RELEASE=${PRODUCTION_RELEASE:-"false"}

export PACKAGE_BRANCH=${PACKAGE_BRANCH:-"branch-3.0.0-alti"}
DEBUG_MAVEN=${DEBUG_MAVEN:-"false"}

if [ "x${PACKAGE_BRANCH}" = "x" ] ; then
  echo "error - PACKAGE_BRANCH is not defined. Please specify the branch explicitly. Exiting!"
  exit -9
fi

echo "ok - extracting git commit label from user defined $PACKAGE_BRANCH"
git_hash=$(git rev-parse HEAD | tr -d '\n')
echo "ok - we are compiling spark branch $PACKAGE_BRANCH upto commit label $git_hash"

# Get a copy of the source code, and tar ball it, remove .git related files
# Rename directory from spark to alti-spark to distinguish 'spark' just in case.
echo "ok - preparing to compile, build, and packaging spark"

if [ "x${HADOOP_VERSION}" = "x" ] ; then
  echo "fatal - HADOOP_VERSION needs to be set, can't build anything, exiting"
  exit -8
else
  export SPARK_HADOOP_VERSION=$HADOOP_VERSION
  echo "ok - applying customized hadoop version $SPARK_HADOOP_VERSION"
fi

if [ "x${HIVE_VERSION}" = "x" ] ; then
  echo "fatal - HIVE_VERSION needs to be set, can't build anything, exiting"
  exit -8
else
  export SPARK_HIVE_VERSION=$HIVE_VERSION
  echo "ok - applying customized hive version $SPARK_HIVE_VERSION"
fi


echo "ok - building Spark examples in directory $(pwd)"
echo "ok - building with HADOOP_VERSION=$SPARK_HADOOP_VERSION HIVE_VERSION=$SPARK_HIVE_VERSION scala=scala-${SCALA_VERSION}"

env | sort

# PURGE LOCAL CACHE for clean build
# mvn dependency:purge-local-repository

########################
# BUILD ENTIRE PACKAGE #
########################
# This will build the overall JARs we need in each folder
# and install them locally for further reference. We assume the build
# environment is clean, so we don't need to delete ~/.ivy2 and ~/.m2
# Default JDK version applied is 1.7 here.

# hadoop.version, yarn.version, and hive.version are all defined in maven profile now
# they are tied to each profile.
# hadoop-2.2 No longer supported, removed.
# hadoop-2.4 hadoop.version=2.4.1 yarn.version=2.4.1 hive.version=0.13.1a hive.short.version=0.13.1
# hadoop-2.6 hadoop.version=2.6.0 yarn.version=2.6.0 hive.version=1.2.1.spark hive.short.version=1.2.1
# hadoop-2.7 hadoop.version=2.7.1 yarn.version=2.7.1 hive.version=1.2.1.spark hive.short.version=1.2.1

testcase_hadoop_profile_str=""
if [[ $SPARK_HADOOP_VERSION == 2.4.* ]] ; then
  testcase_hadoop_profile_str="-Phadoop24-provided"
elif [[ $SPARK_HADOOP_VERSION == 2.6.* ]] ; then
  testcase_hadoop_profile_str="-Phadoop26-provided"
elif [[ $SPARK_HADOOP_VERSION == 2.7.* ]] ; then
  testcase_hadoop_profile_str="-Phadoop27-provided"
else
  echo "fatal - Unrecognize hadoop version $SPARK_HADOOP_VERSION, can't continue, exiting, no cleanup"
  exit -9
fi

# TODO: This needs to align with Maven settings.xml, however, Maven looks for
# -SNAPSHOT in pom.xml to determine which repo to use. This creates a chain reaction on 
# legacy pom.xml design on other application since they are not implemented in the Maven way.
# :-( 
# Will need to create a work around with different repo URL and use profile Id to activate them accordingly
# mvn_release_flag=""
# if [ "x%{_production_release}" == "xtrue" ] ; then
#   mvn_release_flag="-Preleases"
# else
#   mvn_release_flag="-Psnapshots"
# fi

echo "Starting build of sparkexample in $(pwd)"
DATE_STRING=`date +%Y%m%d%H%M%S`
if [ "x${DEBUG_MAVEN}" = "xtrue" ] ; then
  mvn_cmd="mvn -U -X package -Pspark-3.0 -Pkafka10-provided $testcase_hadoop_profile_str --log-file mvnbuild_${DATE_STRING}.log"
else
  mvn_cmd="mvn -U package -Pspark-3.0 -Pkafka10-provided $testcase_hadoop_profile_str --log-file mvnbuild_${DATE_STRING}.log"
fi

echo "$mvn_cmd"
$mvn_cmd
echo ""

if [ $? -ne "0" ] ; then
  echo "fail - sparkexample build failed!"
  popd
  exit -99
fi

# Build RPM
export RPM_EXAMPLE_NAME=`echo alti-spark-${SPARK_VERSION}-example`
export RPM_DESCRIPTION="Apache Spark ${SPARK_VERSION}\n\n${DESCRIPTION}"

DATE_STRING=`date +%Y%m%d%H%M%S`
GIT_REPO="https://github.com/Altiscale/sparkexample"
INSTALL_DIR="${curr_dir}/spark_rpmbuild"
mkdir --mode=0755 -p ${INSTALL_DIR}

export RPM_DIR="${INSTALL_DIR}/rpm/"
mkdir -p --mode 0755 ${RPM_DIR}

echo "Packaging spark example rpm with name ${RPM_NAME} with version ${SPARK_VERSION}-${DATE_STRING} in directory $(pwd)"

##########################
# Spark EXAMPLE RPM #
##########################
export RPM_BUILD_DIR=${INSTALL_DIR}/opt/alti-spark-${SPARK_VERSION}/test_spark
echo "RPM_BUILD_DIR: ${RPM_BUILD_DIR}"

# Generate RPM based on where spark artifacts are placed from previous steps

rm -rf "${RPM_BUILD_DIR}"
echo "mkdir --mode=0755 -p ${RPM_BUILD_DIR}"
mkdir --mode=0755 -p "${RPM_BUILD_DIR}"

# deploy test suite and scripts
echo "cp -rp target/*.jar $RPM_BUILD_DIR/"
cp -rp target/*.jar $RPM_BUILD_DIR/

echo "cp -rp * $RPM_BUILD_DIR/"
cp -rp * $RPM_BUILD_DIR/
rm -rf $RPM_BUILD_DIR/localbuild.sh
rm -rf $RPM_BUILD_DIR/*.log
rm -rf $RPM_BUILD_DIR/sap-xmake-build.sh
rm -rf $RPM_BUILD_DIR/spark_rpmbuild
rm -rf $RPM_BUILD_DIR/README.md

pushd ${RPM_DIR}

fpm --verbose \
--maintainer andrew.lee02@sap.com \
--vendor SAP \
--provides ${RPM_EXAMPLE_NAME} \
--description "$(printf "${RPM_DESCRIPTION}")" \
--replaces ${RPM_EXAMPLE_NAME} \
--url "${GITREPO}" \
--license "Apache License v2" \
--epoch 1 \
--rpm-os linux \
--architecture all \
--category "Development/Libraries" \
-s dir \
-t rpm \
-n ${RPM_EXAMPLE_NAME} \
-v ${SPARK_VERSION} \
--iteration ${DATE_STRING} \
--rpm-user root \
--rpm-group root \
--template-value version=$SPARK_VERSION \
--template-value scala_version=$SCALA_VERSION \
--template-value pkgname=$RPM_EXAMPLE_NAME \
--rpm-auto-add-directories \
-C ${INSTALL_DIR} \
opt

echo "Finished packaging spark example rpm"

if [ $? -ne 0 ] ; then
  echo "FATAL: spark $RPM_EXAMPLE_NAME rpm build fail!"
  popd
  exit -1
fi

mv "${RPM_DIR}${RPM_EXAMPLE_NAME}-${SPARK_VERSION}-${DATE_STRING}.noarch.rpm" "${RPM_DIR}${RPM_EXAMPLE_NAME}.rpm"

echo "ok - spark $RPM_EXAMPLE_NAME and RPM completed successfully!"

exit 0
