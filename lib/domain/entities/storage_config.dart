class StorageConfig {
  final String endpointUrl;
  final String bucketName;
  final String region;
  final String accessKey;
  final String secretKey;
  final int updatedAt;
  const StorageConfig({required this.endpointUrl, required this.bucketName, required this.region, required this.accessKey, required this.secretKey, required this.updatedAt});
}
