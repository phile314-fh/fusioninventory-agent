Name:           perl-FusionInventory-Agent-Task-NetDiscovery
Version:        1.1
Release:        1%{?dist}
Summary:        Network discovery support for FusionInventory Agent
License:        GPLv2+
Group:          Development/Libraries

URL:            http://forge.fusioninventory.org/projects/fusioninventory-agent-task-netdiscovery
Source0:        http://forge.fusioninventory.org/attachments/download/34/FusionInventory-Agent-Task-NetDiscovery-1.1.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

BuildRequires:  perl(ExtUtils::MakeMaker) perl(Module::Install)
# For tests
BuildRequires:  perl(FusionInventory::Agent) >= 2.0

Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl(FusionInventory::Agent) >= 2.0
# Optional (but recommended) dependencies
Requires:       perl(Parallel::ForkManager)
Requires:       perl(Net::SNMP)
Requires:       perl(Nmap::Parser)
Requires:       perl(Net::NBName)
Requires:       nmap


%description
This module scans your networks to get information from devices with
SNMP protocol.


%prep
%setup -q -n FusionInventory-Agent-Task-NetDiscovery-%{version}


%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;

%{_fixperms} $RPM_BUILD_ROOT/*


%check
make test


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc AUTHORS Changes LICENSE README THANKS
%{perl_vendorlib}/FusionInventory/Agent/Task/NetDiscovery*
%{_mandir}/man3/FusionInventory*


%changelog
* Mon May 17 2010 Remi Collet <Fedora@famillecollet.com> 1.1-1
- Specfile autogenerated by cpanspec 1.78.
- spec cleanup

