package FusionInventory::Agent::Task::Inventory::Provider;

use strict;
use warnings;

use Config;
use English qw(-no_match_vars);
use UNIVERSAL::require;

use FusionInventory::Agent::Version;
use FusionInventory::Agent::Logger;
use FusionInventory::Agent::Tools;

# Agent should set this shared variable with early $PROGRAM_NAME content
our $PROGRAM;

sub isEnabled {
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger = $params{logger};

    my $provider = {
        NAME            => $FusionInventory::Agent::Version::PROVIDER,
        VERSION         => $FusionInventory::Agent::Version::VERSION,
        PROGRAM         => $PROGRAM || "$PROGRAM_NAME",
        PERL_EXE        => "$EXECUTABLE_NAME",
        PERL_VERSION    => "$PERL_VERSION"
    };

    my $COMMENTS = $FusionInventory::Agent::Version::COMMENTS || [];
    foreach my $comment (@{$COMMENTS}) {
        push @{$provider->{COMMENTS}}, $comment;
    }

    # Add extra informations in debug level
    if ($logger && $logger->debug_level()) {
        my @uses = ();
        foreach (grep { /^use/ && $Config{$_} } keys(%Config)) {
            push @uses, $Config{$_} =~ /^define|true/ ? $_ : "$_=$Config{$_}";
        }
        $provider->{PERL_CONFIG} = [
            "gccversion: $Config{gccversion}",
            "defines: ".join(' ',@uses)
        ];
        $provider->{PERL_INC} = join(":",@INC);

        $provider->{PERL_ARGS} = "@{$FusionInventory::Agent::Tools::ARGV}"
            if @{$FusionInventory::Agent::Tools::ARGV};

        my @modules = ();
        foreach my $module (qw(
            LWP LWP::Protocol IO::Socket IO::Socket::SSL IO::Socket::INET
            Net::SSLeay Net::HTTPS HTTP::Status HTTP::Response
        )) {
            # Skip not reliable module loading under win32
            next if ($OSNAME eq 'MSWin32' && ($module eq 'IO::Socket::SSL' || $module eq 'Net::HTTPS'));
            $module->require();
            if ($EVAL_ERROR) {
                push @modules, "$module unavailable";
            } else {
                push @modules, $module . ' @ '. VERSION $module ;
                if ($module eq 'Net::SSLeay') {
                    my $sslversion;
                    eval {
                        $sslversion = Net::SSLeay::SSLeay_version(0);
                    };
                    push @modules, $EVAL_ERROR ?
                        "$module fails to load ssl" :
                        "$module uses $sslversion";
                }
            }
        }
        $provider->{PERL_MODULE} = [ @modules ];
    }

    $inventory->addEntry(
        section => 'VERSIONPROVIDER',
        entry   => $provider
    );
}

1;
