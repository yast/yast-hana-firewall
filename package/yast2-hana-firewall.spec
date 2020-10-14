#
# spec file for package yast2-hana-firewall
#
# Copyright (c) 2016 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

Name:           yast2-hana-firewall
Version:        2.0.4
Release:        0
License:        GPL-3.0
Summary:        Assign HANA firewall services to zones
Url:            https://www.suse.com/products/sles-for-sap
Group:          System/YaST
Source:         %{name}-%{version}.tar.bz2
BuildRequires:  yast2 yast2-ruby-bindings yast2-devtools
BuildRequires:  rubygem(yast-rake) rubygem(rspec)
# These dependencies are for running test cases
BuildRequires:  netcfg HANA-Firewall
Requires:       yast2
ExclusiveArch:  x86_64 ppc64le

%description
A utility for assigning HANA firewall services to firewalld zones.

%prep
%setup -q

%check
rake test:unit

%build

%install
rake install DESTDIR="%{buildroot}"

%files
%defattr(-,root,root)
%doc %yast_docdir/
%yast_desktopdir/hana-firewall*
%yast_clientdir/hanafirewall*
%yast_libdir/hanafirewall*

%changelog
