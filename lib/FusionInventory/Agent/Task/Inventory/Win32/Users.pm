package FusionInventory::Agent::Task::Inventory::Win32::Users;

use strict;
use warnings;

use constant wbemFlagReturnImmediately => 0x10;
use constant wbemFlagForwardOnly => 0x20;

use English qw(-no_match_vars);
use Win32::TieRegistry (
    Delimiter   => '/',
    ArrayValues => 0,
    qw/KEY_READ/
);

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Win32;

sub isEnabled {
    my (%params) = @_;
    return 0 if $params{no_category}->{user};
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    if (!$params{no_category}->{local_user}) {
        foreach my $user (_getLocalUsers(logger => $logger)) {
            $inventory->addEntry(
                section => 'LOCAL_USERS',
                entry   => $user
            );
        }
    }

    if (!$params{no_category}->{local_group}) {
        foreach my $group (_getLocalGroups(logger => $logger)) {
            $inventory->addEntry(
                section => 'LOCAL_GROUPS',
                entry   => $group
            );
        }
    }

    foreach my $user (_getLoggedUsers(logger => $logger)) {
        $inventory->addEntry(
            noDuplicated => 1,
            section => 'USERS',
            entry   => $user
        );
    }

    my $lastLoggedUser = _getLastUser(logger => $logger);
    if ($lastLoggedUser) {
        # Include last logged user as usual computer user
        if (ref($lastLoggedUser) eq 'HASH') {
            $inventory->addEntry(
                noDuplicated => 1,
                section => 'USERS',
                entry   => $lastLoggedUser
            );

            # Obsolete in specs, to be removed with 3.0
            $inventory->setHardware({
                LASTLOGGEDUSER => $lastLoggedUser->{LOGIN}
            });
        } else {
            # Obsolete in specs, to be removed with 3.0
            $inventory->setHardware({
                LASTLOGGEDUSER => $lastLoggedUser
            });
        }
    }
}

sub _getLocalUsers {

    my $query =
        "SELECT * FROM Win32_UserAccount " .
        "WHERE LocalAccount='True' AND Disabled='False' and Lockout='False'";

    my @users;

    foreach my $object (getWMIObjects(
        moniker    => 'winmgmts:\\\\.\\root\\CIMV2',
        query      => [ $query ],
        properties => [ qw/Name SID/ ])
    ) {
        my $user = {
            NAME => $object->{Name},
            ID   => $object->{SID},
        };
        push @users, $user;
    }

    return @users;
}

sub _getLocalGroups {

    my $query =
        "SELECT * FROM Win32_Group " .
        "WHERE LocalAccount='True'";

    my @groups;

    foreach my $object (getWMIObjects(
        moniker    => 'winmgmts:\\\\.\\root\\CIMV2',
        query      => [ $query ],
        properties => [ qw/Name SID/ ])
    ) {
        my $group = {
            NAME => $object->{Name},
            ID   => $object->{SID},
        };
        push @groups, $group;
    }

    return @groups;
}

sub _getLoggedUsers {

    my @query = (
        "SELECT * FROM Win32_Process".
        " WHERE ExecutablePath IS NOT NULL" .
        " AND ExecutablePath LIKE '%\\\\Explorer\.exe'", "WQL",
        wbemFlagReturnImmediately | wbemFlagForwardOnly ## no critic (ProhibitBitwise)
    );

    my @users;
    my $seen;

    foreach my $user (getWMIObjects(
        moniker    => 'winmgmts:\\\\.\\root\\CIMV2',
        query      => \@query,
        method     => 'GetOwner',
        params     => [ 'name', 'domain' ],
        name       => [ 'string', '' ],
        domain     => [ 'string', '' ],
        binds      => {
            name    => 'LOGIN',
            domain  => 'DOMAIN'
        })
    ) {
        next if $seen->{$user->{LOGIN}}++;

        push @users, $user;
    }

    return @users;
}

sub _getLastUser {

    my $user;

    return unless any {
        $user = getRegistryValue(path => "HKEY_LOCAL_MACHINE/$_")
    } (
        'SOFTWARE/Microsoft/Windows/CurrentVersion/Authentication/LogonUI/LastLoggedOnSAMUser',
        'SOFTWARE/Microsoft/Windows/CurrentVersion/Authentication/LogonUI/LastLoggedOnUser',
        'SOFTWARE/Microsoft/Windows NT/CurrentVersion/Winlogon/DefaultUserName'
    );

    # LastLoggedOnSAMUser becomes the mandatory value to detect last logged on user
    my @user = $user =~ /^([^\\]*)\\(.*)$/;
    if ( @user == 2 ) {
        # Try to get local user from user part if domain is just a dot
        return $user[0] eq '.' ? _getLocalUser($user[1]) :
            {
                LOGIN   => $user[1],
                DOMAIN  => $user[0]
            };
    }

    # Backward compatibility, to be removed for 3.0
    $user =~ s,.*\\,,;
    return $user;
}

sub _getLocalUser {
    my ($name) = @_;

    my $query = "SELECT * FROM Win32_UserAccount WHERE LocalAccount = True";

    my @local_users = getWMIObjects(
        moniker    => 'winmgmts:\\\\.\\root\\CIMV2',
        query      => [ $query ],
        properties => [ qw/Name Domain/ ]
    );

    my $user = first { $_->{Name} eq $name } @local_users;

    return unless $user;

    return {
        LOGIN   => $user->{Name},
        DOMAIN  => $user->{Domain}
    };
}

1;
