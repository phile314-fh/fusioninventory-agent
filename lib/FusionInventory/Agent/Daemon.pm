package FusionInventory::Agent::Daemon;

use strict;
use warnings;

use Cwd;
use English qw(-no_match_vars);
use UNIVERSAL::require;
use POSIX ":sys_wait_h"; # WNOHANG

use parent 'FusionInventory::Agent';

use FusionInventory::Agent::Logger;
use FusionInventory::Agent::Version;
use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Generic;

my $PROVIDER = $FusionInventory::Agent::Version::PROVIDER;

sub init {
    my ($self, %params) = @_;

    $self->{lastConfigLoad} = time;

    $self->SUPER::init(%params);

    $self->createDaemon();

    # create HTTP interface if required
    $self->loadHttpInterface();

    $self->ApplyServiceOptimizations();

    # install signal handler to handle reload signal
    $SIG{HUP} = sub { $self->reinit(); };
    $SIG{USR1} = sub { $self->runNow(); }
        unless ($OSNAME eq 'MSWin32');
}

sub reinit {
    my ($self) = @_;

    $self->{logger}->debug('agent reinit');

    $self->{lastConfigLoad} = time;

    $self->{config}->reloadFromInputAndBackend();

    # Reload init from parent class
    $self->SUPER::init();

    # Reload HTTP interface if required
    $self->loadHttpInterface();

    $self->ApplyServiceOptimizations();

    $self->{logger}->debug('agent reinit done.');
}

sub run {
    my ($self) = @_;

    $self->setStatus('waiting');

    my @targets = $self->getTargets();

    $self->{logger}->debug("Running in background mode");

    # background mode: work on a targets list copy, but loop while
    # the list really exists so we can stop quickly when asked for
    while ($self->getTargets()) {
        my $time = time();

        @targets = $self->getTargets() unless @targets;
        my $target = shift @targets;

        $self->_reloadConfIfNeeded();

        if ($target->paused()) {
            # Leave immediately if we passed in terminate method
            last unless $self->getTargets();

        } elsif ($time >= $target->getNextRunDate()) {

            my $net_error = 0;
            eval {
                $net_error = $self->runTarget($target);
            };
            $self->{logger}->error($EVAL_ERROR) if $EVAL_ERROR;
            if ($net_error) {
                # Prefer to retry early on net error
                $target->setNextRunDateFromNow(60);
            } else {
                $target->resetNextRunDate();
            }

            # Leave immediately if we passed in terminate method
            last unless $self->getTargets();

            # Call service optimization after each target run
            $self->RunningServiceOptimization();
        }

        # This eventually check for http messages, default timeout is 1 second
        $self->sleep(1);
    }
}

sub runNow {
    my ($self) = @_;

    foreach my $target ($self->getTargets()) {
        $target->setNextRunDateFromNow();
    }

    $self->{logger}->info("$PROVIDER Agent requested to run all targets now");
}

sub _reloadConfIfNeeded {
    my ($self) = @_;

    my $reloadInterval = $self->{config}->{'conf-reload-interval'} || 0;

    return unless ($reloadInterval > 0);

    my $reload = time - $self->{lastConfigLoad} - $reloadInterval;

    $self->reinit() if ($reload > 0);
}

sub runTask {
    my ($self, $target, $name, $response) = @_;

    $self->setStatus("running task $name");

    # server mode: run each task in a child process
    if (my $pid = fork()) {

        # parent
        $self->{current_runtask} = $pid;

        while (waitpid($pid, WNOHANG) == 0) {
            # Wait but eventually handle http server requests
            $self->sleep(1);

            # Leave earlier while requested
            last unless $self->getTargets();
        }
        delete $self->{current_runtask};

    } else {
        # child
        die "fork failed: $ERRNO" unless defined $pid;

        # Don't handle HTTPD interface in forked child
        delete $self->{server};

        # Mostly to update process name on unix platforms
        $self->setStatus("task $name");

        $self->{logger}->debug("forking process $pid to handle task $name");

        $self->runTaskReal($target, $name, $response);

        exit(0);
    }
}

sub createDaemon {
    my ($self) = @_;

    my $config = $self->{config};
    my $logger = $self->{logger};

    # Don't try to create a daemon if configured as a service
    return $logger->info("$PROVIDER Agent service starting")
        if $config->{service};

    $logger->info("$PROVIDER Agent starting");

    my $pidfile = $config->{pidfile} ||
        $self->{vardir} . '/'.lc($PROVIDER).'-agent.pid';

    if ($self->isAlreadyRunning($pidfile)) {
        $logger->error("$PROVIDER Agent is already running, exiting...") if $logger;
        exit 1;
    }

    if (!$config->{'no-fork'}) {

        Proc::Daemon->require();
        if ($EVAL_ERROR) {
            $logger->error("Failed to load Proc::Daemon: $EVAL_ERROR") if $logger;
            exit 1;
        }

        # If we use relative path, we must stay in the current directory
        my $workdir = substr($self->{libdir}, 0, 1) eq '/' ? '/' : getcwd();

        Proc::Daemon::Init(
            {
                work_dir => $workdir,
                pid_file => $pidfile
            }
        );

        $logger->debug("$PROVIDER Agent daemonized") if $logger;
    }
}

sub isAlreadyRunning {
    my ($self, $pidfile) = @_;

    Proc::PID::File->require();
    if ($EVAL_ERROR) {
        $self->{logger}->debug(
            'Proc::PID::File unavailable, unable to check for running agent'
        );
        return 0;
    }

    my $pid = Proc::PID::File->new();
    $pid->{path} = $pidfile;
    return $pid->alive();
}

sub sleep {
    my ($self, $delay) = @_;

    eval {
        local $SIG{CHLD} = sub { die ; };
        if ($self->{server}) {
            # Check for http interface messages, default timeout is 1 second
            $self->{server}->handleRequests() or delay($delay || 1);
        } else {
            delay($delay || 1);
        }
    };
}

sub loadHttpInterface {
    my ($self) = @_;

    my $config = $self->{config};

    if ($config->{'no-httpd'}) {
        # Handle re-init case
        $self->{server}->stop() if ($self->{server});
        return;
    }

    my $logger = $self->{logger};

    my %server_config = (
        logger  => $logger,
        agent   => $self,
        htmldir => $self->{datadir} . '/html',
        ip      => $config->{'httpd-ip'},
        port    => $config->{'httpd-port'},
        trust   => $config->{'httpd-trust'}
    );

    # Handle re-init, don't restart httpd interface unless config changed
    if ($self->{server}) {
        return unless $self->{server}->needToRestart(%server_config);
        $self->{server}->stop();
    }

    FusionInventory::Agent::HTTP::Server->require();
    if ($EVAL_ERROR) {
        $logger->error("Failed to load HTTP server: $EVAL_ERROR");
    } else {
        $self->{server} = FusionInventory::Agent::HTTP::Server->new(%server_config);
        $self->{server}->init();
    }
}

sub ApplyServiceOptimizations {
    my ($self) = @_;

    # Preload all IDS databases to avoid reload them all the time during inventory
    if (grep { /^inventory$/i } @{$self->{tasksExecutionPlan}}) {
        my %datadir = ( datadir => $self->{datadir} );
        getPCIDeviceVendor(%datadir);
        getUSBDeviceVendor(%datadir);
        getEDIDVendor(%datadir);
    }
}

sub RunningServiceOptimization {
    my ($self) = @_;
}

sub terminate {
    my ($self) = @_;

    # Still stop HTTP interface
    $self->{server}->stop() if ($self->{server});

    $self->{logger}->info("$PROVIDER Agent exiting")
        unless ($self->{current_task});

    $self->SUPER::terminate();

    # Kill current forked task
    if ($self->{current_runtask}) {
        kill 'TERM', $self->{current_runtask};
        delete $self->{current_runtask};
    }
}

1;
