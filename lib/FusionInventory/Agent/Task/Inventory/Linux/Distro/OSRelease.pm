package FusionInventory::Agent::Task::Inventory::Linux::Distro::OSRelease;

use strict;
use warnings;

use FusionInventory::Agent::Tools;

sub isEnabled {
  return !canRun('lsb_release') && -r '/etc/os-release';
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $handle = getFileHandle(file => '/etc/os-release');

    my ($name, $version, $description);
    while (my $line = <$handle>) {
        $name        = $1 if $line =~ /^NAME="?([^"]+)"?/;
        $version     = $1 if $line =~ /^VERSION="?([^"]+)"?/;
        $description = $1 if $line =~ /^PRETTY_NAME="?([^"]+)"?/;
    }
    close $handle;

    $inventory->setHardware({
        OSNAME => $description,
    });

    $inventory->setOperatingSystem({
        NAME      => $name,
        VERSION   => $version,
        FULL_NAME => $description
    });

}

1;
