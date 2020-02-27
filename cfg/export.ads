artifacts builderVersion: "1.1", {

  group "com.sap.bds.ats-altiscale", {

    artifact "oozie", {
      file "$gendir/src/sparkexample_rpmbuild/rpm/alti-spark-${buildVersion}-example.rpm"
    }
  }
}
