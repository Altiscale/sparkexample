#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# A demo wrapper shell script for starting the SapSparkSQL shell with HiveContext libraries

# Run the test case as alti-test-01
# /bin/su - alti-test-01 -c "./test_spark/test_spark_shell.sh"

curr_dir=`dirname $0`
curr_dir=`cd $curr_dir; pwd`
testcase_shell_file_01="$curr_dir/vora_scala_test.0.txt"

if [ -z "${SPARK_HOME}" ]; then
  export SPARK_HOME="$(cd "`dirname "$0"`"/..; pwd)"
fi

SPARK_HOME="/opt/alti-spark-1.6.1"

. "${SPARK_HOME}"/bin/load-spark-env.sh
source ${SPARK_HOME}/test_spark/deploy_hive_jar.sh

export HIVE_HOME=${HIVE_HOME:-"/opt/hive"}
export SPARK_VERSION=${SPARK_VERSION:-"1.6.1"}
export SPARK_SCALA_VERSION=${SPARK_SCALA_VERSION:-"2.10"}

spark_conf=${SPARK_CONF_DIR:-"/etc/alti-spark-$SPARK_VERSION"}

pushd $SPARK_HOME

sparksql_hivejars="$SPARK_HOME/sql/hive/target/spark-hive_${SPARK_SCALA_VERSION}-${SPARK_VERSION}.jar"
sparksql_hivethriftjars="$SPARK_HOME/sql/hive-thriftserver/target/spark-hive-thriftserver_${SPARK_SCALA_VERSION}-${SPARK_VERSION}.jar"
hive_jars=$sparksql_hivejars,$sparksql_hivethriftjars

vora_lib=$(rpm -ql $(rpm -qa | grep vora | head -n 1) | grep spark-sap-datasources | grep assembly)

if [ ! -f $vora_lib ] ; then
  2>&1 echo "error - vora lib not found on system, please make sure Vora is isntalled properly!"
  2>&1 echo "error - exiting!!!"
  exit -1
fi

spark_event_log_dir=$(grep 'spark.eventLog.dir' /etc/spark/spark-defaults.conf | tr -s ' ' '\t' | cut -f2)

./bin/spark-shell \
  --master yarn --deploy-mode client \
  --queue research \
  --driver-memory 512M \
  --executor-memory 1G \
  --executor-cores 2 \
  --archives hdfs:///user/$USER/apps/$(basename $(readlink -f $HIVE_HOME))-lib.zip#hive \
  --jars $hive_jars,$vora_lib \
  --driver-class-path $spark_conf/hive-site.xml:$spark_conf/yarnclient-driver-log4j.properties:$HIVE_HOME/lib/* \
  --conf spark.yarn.am.extraJavaOptions="-Djava.library.path=$HADOOP_HOME/lib/native/" \
  --conf spark.executorEnv.LD_PRELOAD='/opt/rh/SAP/lib64/compat-sap-c++.so' \
  --conf spark.executor.extraClassPath=$(basename $sparksql_hivejars):$(basename $sparksql_hivethriftjars) \
  --conf spark.driver.extraJavaOptions="-Dlog4j.configuration=yarnclient-driver-log4j.properties -Djava.library.path=$HADOOP_HOME/lib/native/" \
  --conf spark.eventLog.dir=${spark_event_log_dir}/$USER << EOT
  `cat $testcase_shell_file_01`
EOT

ret_code=$?

popd

reset

exit $ret_code
