# typed: false
# frozen_string_literal: true

# This is a copy of the implementation from the `package_url` gem with the
# following license. Original source can be found at:
# https://github.com/package-url/packageurl-ruby/blob/main/lib/package_url.rb

# MIT License
#
# Copyright (c) 2021 package-url
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require "uri"

# A package URL, or _purl_, is a URL string used to
# identify and locate a software package in a mostly universal and uniform way
# across programing languages, package managers, packaging conventions, tools,
# APIs and databases.
#
# A purl is a URL composed of seven components:
#
# ```
# scheme:type/namespace/name@version?qualifiers#subpath
# ```
#
# For example,
# the package URL for this Ruby package at version 0.1.0 is
# `pkg:ruby/mattt/packageurl-ruby@0.1.0`.
module RubyLsp
  class PackageURL
    # Raised when attempting to parse an invalid package URL string.
    # @see #parse
    class InvalidPackageURL < ArgumentError; end

    # The URL scheme, which has a constant value of `"pkg"`.
    def scheme
      "pkg"
    end

    # The package type or protocol, such as `"gem"`, `"npm"`, and `"github"`.
    attr_reader :type

    # A name prefix, specific to the type of package.
    # For example, an npm scope, a Docker image owner, or a GitHub user.
    attr_reader :namespace

    # The name of the package.
    attr_reader :name

    # The version of the package.
    attr_reader :version

    # Extra qualifying data for a package, specific to the type of package.
    # For example, the operating system or architecture.
    attr_reader :qualifiers

    # An extra subpath within a package, relative to the package root.
    attr_reader :subpath

    # Constructs a package URL from its components
    # @param type [String] The package type or protocol.
    # @param namespace [String] A name prefix, specific to the type of package.
    # @param name [String] The name of the package.
    # @param version [String] The version of the package.
    # @param qualifiers [Hash] Extra qualifying data for a package, specific to the type of package.
    # @param subpath [String] An extra subpath within a package, relative to the package root.
    def initialize(type:, name:, namespace: nil, version: nil, qualifiers: nil, subpath: nil)
      raise ArgumentError, "type is required" if type.nil? || type.empty?
      raise ArgumentError, "name is required" if name.nil? || name.empty?

      @type = type.downcase
      @namespace = namespace
      @name = name
      @version = version
      @qualifiers = qualifiers
      @subpath = subpath
    end

    # Creates a new PackageURL from a string.
    # @param [String] string The package URL string.
    # @raise [InvalidPackageURL] If the string is not a valid package URL.
    # @return [PackageURL]
    def self.parse(string)
      components = {
        type: nil,
        namespace: nil,
        name: nil,
        version: nil,
        qualifiers: nil,
        subpath: nil,
      }

      # Split the purl string once from right on '#'
      # - The left side is the remainder
      # - Strip the right side from leading and trailing '/'
      # - Split this on '/'
      # - Discard any empty string segment from that split
      # - Discard any '.' or '..' segment from that split
      # - Percent-decode each segment
      # - UTF-8-decode each segment if needed in your programming language
      # - Join segments back with a '/'
      # - This is the subpath
      case string.rpartition("#")
      in String => remainder, separator, String => subpath unless separator.empty?
        subpath_components = []
        subpath.split("/").each do |segment|
          next if segment.empty? || segment == "." || segment == ".."

          subpath_components << URI.decode_www_form_component(segment)
        end

        components[:subpath] = subpath_components.compact.join("/")

        string = remainder
      else
        components[:subpath] = nil
      end

      # Split the remainder once from right on '?'
      # - The left side is the remainder
      # - The right side is the qualifiers string
      # - Split the qualifiers on '&'. Each part is a key=value pair
      # - For each pair, split the key=value once from left on '=':
      # - The key is the lowercase left side
      # - The value is the percent-decoded right side
      # - UTF-8-decode the value if needed in your programming language
      # - Discard any key/value pairs where the value is empty
      # - If the key is checksums,
      #   split the value on ',' to create a list of checksums
      # - This list of key/value is the qualifiers object
      case string.rpartition("?")
      in String => remainder, separator, String => qualifiers unless separator.empty?
        components[:qualifiers] = {}

        qualifiers.split("&").each do |pair|
          case pair.partition("=")
          in String => key, separator, String => value unless separator.empty?
            key = key.downcase
            value = URI.decode_www_form_component(value)
            next if value.empty?

            components[:qualifiers][key] = case key
            when "checksums"
              value.split(",")
            else
              value
            end
          else
            next
          end
        end

        string = remainder
      else
        components[:qualifiers] = nil
      end

      # Split the remainder once from left on ':'
      # - The left side lowercased is the scheme
      # - The right side is the remainder
      case string.partition(":")
      in "pkg", separator, String => remainder unless separator.empty?
        string = remainder
      else
        raise InvalidPackageURL, 'invalid or missing "pkg:" URL scheme'
      end

      # Strip the remainder from leading and trailing '/'
      # Use gsub to remove ALL leading slashes instead of just one
      string = string.gsub(%r{^/+}, "").delete_suffix("/")
      # - Split this once from left on '/'
      # - The left side lowercased is the type
      # - The right side is the remainder
      case string.partition("/")
      in String => type, separator, remainder unless separator.empty?
        components[:type] = type

        string = remainder
      else
        raise InvalidPackageURL, "invalid or missing package type"
      end

      # Split the remainder once from right on '@'
      # - The left side is the remainder
      # - Percent-decode the right side. This is the version.
      # - UTF-8-decode the version if needed in your programming language
      # - This is the version
      case string.rpartition("@")
      in String => remainder, separator, String => version unless separator.empty?
        components[:version] = URI.decode_www_form_component(version)

        string = remainder
      else
        components[:version] = nil
      end

      # Split the remainder once from right on '/'
      # - The left side is the remainder
      # - Percent-decode the right side. This is the name
      # - UTF-8-decode this name if needed in your programming language
      # - Apply type-specific normalization to the name if needed
      # - This is the name
      case string.rpartition("/")
      in String => remainder, separator, String => name unless separator.empty?
        components[:name] = URI.decode_www_form_component(name)

        # Split the remainder on '/'
        # - Discard any empty segment from that split
        # - Percent-decode each segment
        # - UTF-8-decode the each segment if needed in your programming language
        # - Apply type-specific normalization to each segment if needed
        # - Join segments back with a '/'
        # - This is the namespace
        components[:namespace] = remainder.split("/").map { |s| URI.decode_www_form_component(s) }.compact.join("/")
      in _, _, String => name
        components[:name] = URI.decode_www_form_component(name)
        components[:namespace] = nil
      end

      # Ensure type and name are not nil before creating the PackageURL instance
      raise InvalidPackageURL, "missing package type" if components[:type].nil?
      raise InvalidPackageURL, "missing package name" if components[:name].nil?

      # Create a new PackageURL with validated components
      type = components[:type] || ""  # This ensures type is never nil
      name = components[:name] || ""  # This ensures name is never nil

      new(
        type: type,
        name: name,
        namespace: components[:namespace],
        version: components[:version],
        qualifiers: components[:qualifiers],
        subpath: components[:subpath],
      )
    end

    # Returns a hash containing the
    # scheme, type, namespace, name, version, qualifiers, and subpath components
    # of the package URL.
    def to_h
      {
        scheme: scheme,
        type: @type,
        namespace: @namespace,
        name: @name,
        version: @version,
        qualifiers: @qualifiers,
        subpath: @subpath,
      }
    end

    # Returns a string representation of the package URL.
    # Package URL representations are created according to the instructions from
    # https://github.com/package-url/purl-spec/blob/0b1559f76b79829e789c4f20e6d832c7314762c5/PURL-SPECIFICATION.rst#how-to-build-purl-string-from-its-components.
    def to_s
      # Start a purl string with the "pkg:" scheme as a lowercase ASCII string
      purl = "pkg:"

      # Append the type string to the purl as a lowercase ASCII string
      # Append '/' to the purl

      purl += @type
      purl += "/"

      # If the namespace is not empty:
      # - Strip the namespace from leading and trailing '/'
      # - Split on '/' as segments
      # - Apply type-specific normalization to each segment if needed
      # - UTF-8-encode each segment if needed in your programming language
      # - Percent-encode each segment
      # - Join the segments with '/'
      # - Append this to the purl
      # - Append '/' to the purl
      # - Strip the name from leading and trailing '/'
      # - Apply type-specific normalization to the name if needed
      # - UTF-8-encode the name if needed in your programming language
      # - Append the percent-encoded name to the purl
      #
      # If the namespace is empty:
      # - Apply type-specific normalization to the name if needed
      # - UTF-8-encode the name if needed in your programming language
      # - Append the percent-encoded name to the purl
      case @namespace
      in String => namespace unless namespace.empty?
        segments = []
        @namespace.delete_prefix("/").delete_suffix("/").split("/").each do |segment|
          next if segment.empty?

          segments << URI.encode_www_form_component(segment)
        end
        purl += segments.join("/")

        purl += "/"
        purl += URI.encode_www_form_component(@name.delete_prefix("/").delete_suffix("/"))
      else
        purl += URI.encode_www_form_component(@name)
      end

      # If the version is not empty:
      # - Append '@' to the purl
      # - UTF-8-encode the version if needed in your programming language
      # - Append the percent-encoded version to the purl
      case @version
      in String => version unless version.empty?
        purl += "@"
        purl += URI.encode_www_form_component(@version)
      else
        nil
      end

      # If the qualifiers are not empty and not composed only of key/value pairs
      # where the value is empty:
      # - Append '?' to the purl
      # - Build a list from all key/value pair:
      # - discard any pair where the value is empty.
      # - UTF-8-encode each value if needed in your programming language
      # - If the key is checksums and this is a list of checksums
      #   join this list with a ',' to create this qualifier value
      # - create a string by joining the lowercased key,
      #   the equal '=' sign and the percent-encoded value to create a qualifier
      # - sort this list of qualifier strings lexicographically
      # - join this list of qualifier strings with a '&' ampersand
      # - Append this string to the purl
      case @qualifiers
      in Hash => qualifiers unless qualifiers.empty?
        list = []
        qualifiers.each do |key, value|
          next if value.empty?

          list << case [key, value]
          in "checksums", Array => checksums
            "#{key.downcase}=#{checksums.join(",")}"
          else
            "#{key.downcase}=#{URI.encode_www_form_component(value)}"
          end
        end

        unless list.empty?
          purl += "?"
          purl += list.sort.join("&")
        end
      else
        nil
      end

      # If the subpath is not empty and not composed only of
      # empty, '.' and '..' segments:
      # - Append '#' to the purl
      # - Strip the subpath from leading and trailing '/'
      # - Split this on '/' as segments
      # - Discard empty, '.' and '..' segments
      # - Percent-encode each segment
      # - UTF-8-encode each segment if needed in your programming language
      # - Join the segments with '/'
      # - Append this to the purl
      case @subpath
      in String => subpath unless subpath.empty?
        segments = []
        subpath.delete_prefix("/").delete_suffix("/").split("/").each do |segment|
          next if segment.empty? || segment == "." || segment == ".."

          # Custom encoding for URL fragment segments:
          # 1. Explicitly encode % as %25 to prevent double-encoding issues
          # 2. Percent-encode special characters according to URL fragment rules
          # 3. This ensures proper round-trip encoding/decoding with the parse method
          segments << segment.gsub(/%|[^A-Za-z0-9\-\._~]/) do |m|
            m == "%" ? "%25" : format("%%%02X", m.ord)
          end
        end

        unless segments.empty?
          purl += "#"
          purl += segments.join("/")
        end
      else
        nil
      end

      purl
    end

    # Returns an array containing the
    # scheme, type, namespace, name, version, qualifiers, and subpath components
    # of the package URL.
    def deconstruct
      [scheme, @type, @namespace, @name, @version, @qualifiers, @subpath]
    end

    # Returns a hash containing the
    # scheme, type, namespace, name, version, qualifiers, and subpath components
    # of the package URL.
    def deconstruct_keys(_keys)
      to_h
    end
  end
end
