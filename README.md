[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/CandoImage/ddev-silo/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/CandoImage/ddev-silo/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/CandoImage/ddev-silo)](https://github.com/CandoImage/ddev-silo/commits)
[![release](https://img.shields.io/github/v/release/CandoImage/ddev-silo)](https://github.com/CandoImage/ddev-silo/releases/latest)

# DDEV Silo

This add-on integrates [Silo](https://silo.pgsty.com/), a drop-in replacement for MinIO, into your [DDEV](https://ddev.com/) project.

It is based on the [ddev/ddev-minio](https://github.com/ddev/ddev-minio) add-on, which has been archived because the upstream MinIO repository is archived and the `minio/minio` Docker image is gone. The add-on keeps the MinIO names working, so projects using ddev-minio can switch without changing their configuration (see [Migrating from ddev-minio](#migrating-from-ddev-minio)).

## Overview

Silo is an S3-compatible object storage system and a drop-in replacement for [MinIO](https://min.io/). It is capable of working with unstructured data such as photos, videos, log files, backups, and container images.

## Installation

```sh
ddev add-on get CandoImage/ddev-silo
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev silo` | Open Silo console in your browser (`https://<project>.ddev.site:9090`) |
| `ddev mc` | Run MinIO client (`mc`); both `silo` and `minio` are configured as aliases, e.g. `ddev mc ls silo` |
| `ddev logs -s silo` | Check Silo logs |
| `ddev ssh -s silo` | Open a shell in the Silo container |

### Console credentials

Either login works:

| Username    | Password    | Notes                                                       |
|-------------|-------------|-------------------------------------------------------------|
| `ddevminio` | `ddevminio` | Root user, also used as S3 access key / secret              |
| `ddevsilo`  | `ddevsilo`  | Admin user (`consoleAdmin` policy), created on `ddev start` |

The `ddevsilo` user is created by a `post-start` hook in `.ddev/config.silo.yaml`. It can also be used as S3 access key / secret.

### File access

Project docker instances can access the S3 API via `http://silo:10101` (`http://minio:10101` works too).

DDEV router is configured to proxy the requests to `https://<project>.ddev.site:10101` to the S3 API.

Example URLs for accessing files are

| Bucket   | File path              | Internal URL                                    | External URL                                                    |
|----------|------------------------|-------------------------------------------------|-----------------------------------------------------------------|
| `photos` | `vacation/seaside.jpg` | `http://silo:10101/photos/vacation/seaside.jpg` | `https://<project>.ddev.site:10101/photos/vacation/seaside.jpg` |
| `music`  | `tron/derezzed.mp3`    | `http://silo:10101/music/tron/derezzed.mp3`     | `https://<project>.ddev.site:10101/music/tron/derezzed.mp3`     |

## Connecting from PHP

### Installation

Since Silo is S3 compatible you can use [AWS PHP SDK](https://packagist.org/packages/aws/aws-sdk-php). Install it with composer:

```bash
ddev composer require aws/aws-sdk-php
```

### Basic usage

```php
<?php

require __DIR__ . '/vendor/autoload.php';

$s3 = new \Aws\S3\S3Client([
    'endpoint' => 'http://silo:10101',
    'credentials' => [
        'key' => 'ddevminio',
        'secret' => 'ddevminio',
    ],
    'region' => 'us-east-1',
    'version' => 'latest',
    'use_path_style_endpoint' => true,
]);

$bucketName = 'ddev-silo';

if (!$s3->doesBucketExist($bucketName)) {
    $s3->createBucket([
        'Bucket' => $bucketName,
    ]);
}

$s3->putObject([
    'Bucket' => $bucketName,
    'Key' => 'ddev-test',
    'Body' => 'DDEV Silo is working!',
]);

$object = $s3->getObject([
    'Bucket' => $bucketName,
    'Key' => 'ddev-test',
]);

echo $object['Body'];
```

## Advanced Customization

To change the Docker image:

```bash
ddev dotenv set .ddev/.env.silo --silo-docker-image=pgsty/silo:latest
ddev add-on get CandoImage/ddev-silo
ddev restart
```

An existing `MINIO_DOCKER_IMAGE` setting in `.ddev/.env.minio` is still honored when `SILO_DOCKER_IMAGE` is not set.

You can modify `.ddev/docker-compose.silo.yaml` directly by removing the `#ddev-generated` line, but it's recommended to use a separate `.ddev/docker-compose.silo_extra.yaml` file for overrides, for example:

```yaml
services:
  silo:
    command: server --console-address :9090 --address :10101

configs:
  mc-config.json:
    content: |
      {
        "version": "10",
        "aliases": {
          "silo": {
            "url": "http://localhost:10101",
            "accessKey": "ddevminio",
            "secretKey": "ddevminio",
            "api": "s3v4",
            "path": "auto"
          },
          "minio": {
            "url": "http://localhost:10101",
            "accessKey": "ddevminio",
            "secretKey": "ddevminio",
            "api": "s3v4",
            "path": "auto"
          }
        }
      }
```

## Migrating from ddev-minio

Install this add-on over the existing one and restart:

```sh
ddev add-on get CandoImage/ddev-silo
ddev restart
```

The installer removes the old `#ddev-generated` MinIO files and the old `ddev-<project>-minio` container. Your data is kept: Silo uses the same `ddev-<project>-minio` Docker volume.

The old `minio` add-on is also unregistered, so it no longer shows up in `ddev add-on list --installed`. There's no need to run `ddev add-on remove minio` afterwards.

What keeps working unchanged:

| ddev-minio                                 | ddev-silo                                           |
|--------------------------------------------|-----------------------------------------------------|
| `http://minio:10101`                       | Still works (`http://silo:10101` is preferred)      |
| `ddev minio`                               | Still works, alias for `ddev silo`                  |
| `ddev mc ... minio/...`                    | Still works (`silo/...` is preferred)               |
| `ddevminio` / `ddevminio` login            | Unchanged (`ddevsilo` / `ddevsilo` is added)        |
| `MINIO_DOCKER_IMAGE` in `.ddev/.env.minio` | Still honored, `SILO_DOCKER_IMAGE` takes precedence |

What changes:

- The service is named `silo`, so use `-s silo` with `ddev logs`, `ddev ssh` and `ddev exec`.
- Overrides in `.ddev/docker-compose.minio_extra.yaml` that target the `minio` service need to target `silo` instead.
- If a modified (non-`#ddev-generated`) `docker-compose.minio.yaml` or `commands/minio/mc` is present, the installer stops and asks you to remove it.

## Credits

**[ddev-minio](https://github.com/ddev/ddev-minio)** 
  * Contributed by [Oblak Studio](https://github.com/oblakstudio)
  * Maintained by the [DDEV team](https://ddev.com/support-ddev/)

**[ddev-silo](https://github.com/ddev/ddev-silo)**
  * Contributed by [Cando Image GmbH](https://github.com/CandoImage)
