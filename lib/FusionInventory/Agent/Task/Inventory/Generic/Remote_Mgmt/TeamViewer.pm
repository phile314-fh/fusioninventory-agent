package FusionInventory::Agent::Task::Inventory::Generic::Remote_Mgmt::TeamViewer;

use strict;
use warnings;

use English qw(-no_match_vars);

use FusionInventory::Agent::Tools;

sub isEnabled {
    my (%params) = @_;

    if ($OSNAME eq 'MSWin32') {

        FusionInventory::Agent::Tools::Win32->use();

        my $key = getRegistryKey(
            path => is64bit() ?
                "HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/TeamViewer" :
                "HKEY_LOCAL_MACHINE/SOFTWARE/TeamViewer",
            logger => $params{logger}
        );
        return $key && (keys %$key);
    } elsif ($OSNAME eq 'darwin') {
        return canRun('defaults') && grep { -e $_ } map {
            "/Library/Preferences/com.teamviewer.teamviewer$_.plist"
        } qw( .preferences 10 9 8 7 );
    }

    return canRun('teamviewer');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $teamViewerID = _getID(logger => $logger);
    if (defined($teamViewerID)) {
        $logger->debug('Found TeamViewerID : ' . $teamViewerID) if ($logger);

        $inventory->addEntry(
            section => 'REMOTE_MGMT',
            entry   => {
                ID   => $teamViewerID,
                TYPE => 'teamviewer'
            }
        );
    } else {
        $logger->debug('TeamViewerID not found') if ($logger);
    }
}

sub _getID {
    my (%params) = @_;

    if ($OSNAME eq 'MSWin32') {

        FusionInventory::Agent::Tools::Win32->use();

        my $clientid = getRegistryValue(
            path   => is64bit() ?
                "HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/TeamViewer/ClientID" :
                "HKEY_LOCAL_MACHINE/Software/TeamViewer/ClientID",
            %params
        );

        unless ($clientid) {
            my $teamviever_reg = getRegistryKey(
                path => is64bit() ?
                    "HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/TeamViewer" :
                    "HKEY_LOCAL_MACHINE/SOFTWARE/TeamViewer",
                logger => $params{logger}
            );

            # Look for subkey beginning with Version
            foreach my $key (keys(%{$teamviever_reg})) {
                next unless $key =~ /^Version\d+\//;
                $clientid = $teamviever_reg->{$key}->{"/ClientID"};
                last if (defined($clientid));
            }
        }

        return $clientid ? hex($clientid) || $clientid : undef ;
    }

    if ($OSNAME eq 'darwin') {
        my ( $plist_file ) = grep { -e $_ } map {
            "/Library/Preferences/com.teamviewer.teamviewer$_.plist"
        } qw( .preferences 10 9 8 7 );

        return getFirstLine( command => "defaults read $plist_file ClientID" ) ;
    }

    return getFirstMatch(
        command => "teamviewer --info",
        pattern => qr/TeamViewer ID:(?:\033\[0m|\s)*(\d+)\s+/,
        %params
    );
}

1;
