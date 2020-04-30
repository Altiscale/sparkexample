artifacts builderVersion: "1.1", {

  group "com.sap.bds.ats-altiscale", {
    artifact "sparkexample", {
      file "$gendir/src/spark_rpmbuild/rpm/alti-spark-3.0.0-example.rpm"
    }
  }
}
