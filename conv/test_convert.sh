#!/bin/bash

test_to_snake_case() {
  local test_table=(
    "$(convert::to_snake_case "camelCase")" "camel_case"
    "$(convert::to_snake_case "PascalCase")" "pascal_case"
    "$(convert::to_snake_case "dash-case")" "dash_case"
    "$(convert::to_snake_case "XMLParser")" "xml_parser"
    "$(convert::to_snake_case "myHTTPSClient")" "my_https_client"
    "$(convert::to_snake_case "already_snake")" "already_snake"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}

test_to_camel_case() {
  local test_table=(
    "$(convert::to_camel_case "dash-case")" "dashCase"
    "$(convert::to_camel_case "PascalCase")" "pascalCase"
    "$(convert::to_camel_case "snake_case")" "snakeCase"
    "$(convert::to_camel_case "_foo_bar")" "_fooBar"
    "$(convert::to_camel_case "foo_bar_baz")" "fooBarBaz"
    "$(convert::to_camel_case "alreadyCamel")" "alreadyCamel"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}

test_to_dash_case() {
  local test_table=(
    "$(convert::to_dash_case "camelCase")" "camel-case"
    "$(convert::to_dash_case "PascalCase")" "pascal-case"
    "$(convert::to_dash_case "snake_case")" "snake-case"
    "$(convert::to_dash_case "XMLParser")" "xml-parser"
    "$(convert::to_dash_case "myHTTPSClient")" "my-https-client"
    "$(convert::to_dash_case "already-dash")" "already-dash"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}

test_to_pascal_case() {
  local test_table=(
    "$(convert::to_pascal_case "camelCase")" "CamelCase"
    "$(convert::to_pascal_case "dash-case")" "DashCase"
    "$(convert::to_pascal_case "snake_case")" "SnakeCase"
    "$(convert::to_pascal_case "foo_bar_baz")" "FooBarBaz"
    "$(convert::to_pascal_case "AlreadyPascal")" "AlreadyPascal"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}

test_ipv4_to_int() {
  local test_table=(
    "$(convert::ipv4_to_int "172.16.0.100")" "2886729828"
    "$(convert::ipv4_to_int "192.168.1.180")" "3232235956"
    "$(convert::ipv4_to_int "0.0.0.0")" "0"
    "$(convert::ipv4_to_int "255.255.255.255")" "4294967295"
    "$(convert::ipv4_to_int "127.0.0.1")" "2130706433"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}

test_int_to_ipv4() {
  local test_table=(
    "$(convert::int_to_ipv4 "2886729828")" "172.16.0.100"
    "$(convert::int_to_ipv4 "3232235956")" "192.168.1.180"
    "$(convert::int_to_ipv4 "0")" "0.0.0.0"
    "$(convert::int_to_ipv4 "4294967295")" "255.255.255.255"
    "$(convert::int_to_ipv4 "2130706433")" "127.0.0.1"
  )
  for ((i = 0; i < ${#test_table[@]}; i += 2)); do
    local actual_value="${test_table[i]}"
    local expected_value="${test_table[i+1]}"
    [[ "${actual_value}" == "${expected_value}" ]] || $report_failed "expected: ${expected_value}, got: ${actual_value}"
  done
  return $TEST_RESULT
}
