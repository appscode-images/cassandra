#!/usr/bin/env bash
set -Eeuo pipefail

# https://cassandra.apache.org/doc/5.0/cassandra/installing/installing.html#prerequisites
# https://cassandra.apache.org/doc/4.1/cassandra/getting_started/installing.html#prerequisites
# https://cassandra.apache.org/doc/3.11/cassandra/getting_started/installing.html#prerequisites
defaultJavaVersion='17'
declare -A javaVersions=(
	[3.0]='8'
	[3.11]='8'
	[4.0]='11'
	[4.1]='11'
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	export version

	possibleVersions=( $(
		git ls-remote --tags 'https://gitbox.apache.org/repos/asf/cassandra.git' "refs/tags/cassandra-$version*" \
			| cut -d/ -f3- \
			| cut -d^ -f1 \
			| cut -d- -f2- \
			| sort -urV
	) )

	fullVersion=
	sha512=
	for possibleVersion in "${possibleVersions[@]}"; do
		if sha512="$(wget -qO- "https://downloads.apache.org/cassandra/$possibleVersion/apache-cassandra-$possibleVersion-bin.tar.gz.sha512" | grep -oE '[a-f0-9]{128}')" && [ -n "$sha512" ]; then
			fullVersion="$possibleVersion"
			break
		fi
	done
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: failed to find full version for $version"
		exit 1
	fi
	export fullVersion sha512

	export javaVersion="${javaVersions[$version]:-$defaultJavaVersion}"

	# for the given Java version, find the "default" Eclipse Temurin tag with stable specificity ("X-jre-SUITE")
	from="$(
		bashbrew --arch amd64 list --arch-filter "https://github.com/docker-library/official-images/raw/HEAD/library/eclipse-temurin:$javaVersion-jre" \
			| grep -F ":$javaVersion-jre-" \
			| tail -1
	)"
	export from

	echo "$version: $fullVersion (FROM $from)"

	json="$(jq <<<"$json" -c '
		.[env.version] = {
			version: env.fullVersion,
			sha512: env.sha512,
			java: {
				version: env.javaVersion,
			},
			FROM: {
				# this structure is a little bit awkward, but gives us nice commit messages like "Update 5.0 to FROM eclipse-temurin:17-jre-jammy"
				version: env.from,
				base: (env.from | split(":\(env.javaVersion)-jre-")[1]),
			},
		}
	')"
done

jq <<<"$json" . > versions.json
