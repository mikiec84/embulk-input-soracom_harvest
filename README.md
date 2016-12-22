# SORACOM Harvest input plugin for Embulk

[SORACOM Harvest](https://soracom.jp/services/harvest/) is the data store service to store the data collected from IoT devices.
This plugin allows you to load data from Soracom Harvest and load into other data store and RDBMS with other [Embulk plugins](http://www.embulk.org/plugins/).

## Overview

* **Plugin type**: input
* **Resume supported**: yes
* **Cleanup supported**: yes
* **Guess supported**: yes

## Configuration

- **auth_key_id**: AUTH_KEY for SORACOM (string, required)
- **auth_key**: AUTH_KEY_ID for SORACOM (string, required)
- **target**: 'harvest' or 'sims'(string, default: 'harvest')
- **filter**: filter to when get SIMs(string, default: `null`)
- **tag_value_match_mode**: Tag search mode exact` or `prefix` (string, optional, default: `exact`)
<!-- - **incremental**: enables incremental loading(boolean, default: true). If incremental loading is enabled, config diff for the next execution will include `last_path` parameter so that next execution skips files before the path. Otherwise, `last_path` will not be included.-->
- **start_datetime**: get data time is after this value (works only when target is 'harvest')
- **end_datetime**: get data time is after this value (works only when target is 'harvest')
- **retry_limit**: Try to retry this times (integer, default: 5)
- **retry_initial_wait_sec**: Wait seconds for exponential backoff initial value (integer, default: 2)
- **endpoint**: endpoint url of SORACOM API server. e.g. "https://api.soracom.io/v1" (string, default: `null`)

## Example

```yaml
in:
  type: soracom_harvest
  auth_key_id: keyId-ABCDEFGHIJKLMNOPQRSTUVWXYZ
  auth_key: secret-abcdefghijklmnopqrstuvwxyz
  tartet: harvest
  filter: status: active|ready
  start_datetime: '2016-07-01T13:12:59.035692+09:00'
  end_datetime: '2017-01-05T16:32:43.021312+09:00'
```

# Usage

1. Please configure minimum seed config.
2. Run `embulk guess /path/to/seed.yml -o /path/to/config.yml`.
    * If you have no registered SIMs, guess doesn't work.
    * If you have no records at Harvest, guess doesn't work.
3. Run `embulk preview /path/to/config.yml`
4. Run `embulk run /path/to/config.yml`

### filter

You can filter SIMS when get data by filter option.

This plugin doesn't support multiple filter condition.

#### imsi

```yaml
filter: imsi: 440123456789012
```

#### msisdn

```yaml
filter: msisdn: 811234567890
```

#### status

```yaml
filter: status: active
```

```yaml
filter: status: active|ready
```

status value can be taken (active, inactive, ready, instock, shipped, suspended, terminated).

Also accepts multiple vaules separated with `|`

#### speed_class

```yaml
filter: speed_class: s1.minimum
```

```yaml
filter: speed_class: s1.minimum|s1.slow
```

#### tag

```yaml
filter: tag_name: tag_value
tag_value_match_mode: exact # or 'prefix'
```

You can set `tag_value_match_mode`. This option can be taken (exact, prefix).


### FAQ

* Q1. I stores data at SORACOM Harvest with **JSON** format and want to expand its columns.

  * A. Please use [embulk-filter_expand_json](https://github.com/civitaspo/embulk-filter-expand_json)

* Q2. I want to filter by value with more complex conditions like SQL.

  * A. Please use [embulk-filter-row](https://github.com/sonots/embulk-filter-row)

* Q3. Want to drop column.

  * A. Please use[embulk-filter-column](https://github.com/sonots/embulk-filter-column)

* Q4. Want to add time column like current time.

  * A. Use [embulk-filter-add_time](https://github.com/treasure-data/embulk-filter-add_time)


## Build

```
$ rake
```

## Development

```
$ git clone git@github.com:sakama/embulk-input-soracom_harvest.git
$ cd embulk-input-soracom_harvest
$ embulk bundle install --path vendor/bundle
$ embulk run -I ./lib /path/to/config.yml
```
