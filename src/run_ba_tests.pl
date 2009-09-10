#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  run_ba_tests.pl
#
#        USAGE:  ./run_ba_tests.pl 
#
#  DESCRIPTION:  Runs a set of bundle adjustment tests
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Styer, <michael@styer.net>
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  09/03/2009 02:24:05 PM PDT
#     REVISION:  ---
#===============================================================================

use File::Path qw(make_path);
use Statistics::Descriptive;
use strict;
#use warnings;

##
## CONFIGURATION
##

my $make_data          = './make_ba_test_data';
my $ba_test            = './ba_test';
my $ba_test_cfg        = 'ba_test.cfg';
my $tests_root         = 'ba_tests';
my $data_dir_prefix    = 'test_plan';

my $control_net_file   = 'noisy_control.cnet';
my $camera_prefix      = "noisy_camera";
#my $camera_prefix      = "camera";
my $camera_ext         = "tsai";
my @ba_types = ('sparse', 
                'robust_sparse');

my $wp_true_file   = "wp_ground_truth.txt";
my $wp_init_file   = "wp_initial.txt";
my $wp_final_file  = "wp_final.txt";
my $cam_true_file  = "cam_ground_truth.txt";
my $cam_init_file  = "cam_initial.txt";
my $cam_final_file = "cam_final.txt";
my $num_tests = 100;
my $ba_report_level = 0;
my $percentile_low  = 5;
my $percentile_high = 95;


# Default values
my %test_config = (
    "pixel-inlier-noise-type"  => "normal",
    "pixel-inlier-df"          => 1,
    "pixel-inlier-sigma"       => 1,
    "pixel-outlier-noise-type" => "normal",
    "pixel-outlier-df"         => 1,
    "pixel-outlier-sigma"      => 1,
    "pixel-outlier-freq"       => 0.0,
    "xyz-inlier-noise-type"    => "normal",
    "xyz-inlier-df"            => 1,
    "xyz-inlier-sigma"         => 100,
    "xyz-outlier-noise-type"   => "normal",
    "xyz-outlier-df"           => 1,
    "xyz-outlier-sigma"        => 1,
    "xyz-outlier-freq"         => 0.0,
    "euler-inlier-noise-type"  => "normal",
    "euler-inlier-df"          => 1,
    "euler-inlier-sigma"       => 0.1,
    "euler-outlier-noise-type" => "normal",
    "euler-outlier-df"         => 1,
    "euler-outlier-sigma"      => 1,
    "euler-outlier-freq"       => 0.0,
    "min-tiepoints-per-image"  => 20,
    "number-of-cameras"        => 3,
    "lambda"                   => 1,
    "camera-position-sigma"    => 1,
    "camera-pose-sigma"        => 1,
    "max-iterations"           => 30,
    "cnet"                     => $control_net_file
);

##
## SUBROUTINES
##

sub read_wp_results {
    my $fname = shift;
    my $ret = [];
    open (FILE, $fname) or die "Error: failed opening $fname: $!\n";
    while (<FILE>) {
        chomp;
        push(@$ret, split /\t/);
    }
    return $ret;
}

sub read_cam_results {
    my $fname = shift;
    my $xyz_ret = [];
    my $euler_ret = [];
    open (FILE, $fname) or die "Error: failed opening $fname: $!\n";
    while (<FILE>) {
        chomp;
        my ($x, $y, $z, @euler) = split /\t/;
        push(@$xyz_ret, ($x, $y, $z));
        push(@$euler_ret, @euler);
    }
    return ($xyz_ret, $euler_ret);
}

sub mse {
    my $a1 = shift;
    my $a2 = shift;
    my $size = scalar @$a1;
    die "Error: different size arrays passed to mse()\n" unless scalar @$a2 == $size;
    my $stat = Statistics::Descriptive::Sparse->new();
    my @sqerr = map {($a1->[$_] - $a2->[$_])**2} (0 .. $size-1);
    $stat->add_data(@sqerr);
    return $stat->mean();
}

sub read_test_plans {
    my ($test_plan_file, $num_test_plans) = @_;
    die "Error: must provide a test plan\n" unless defined $test_plan_file;
    my %test_plans = ();

    open (TEST_PLAN, "<$test_plan_file") 
        or die "Error: failed opening $test_plan_file: $!\n";
    my @test_params = split(/\t/, <TEST_PLAN>);
    map { chomp; s/[^\w]$//; $test_plans{$_} = []; } @test_params;
    while (<TEST_PLAN>) { 
        chomp;
        my @vals = split /\t/;
        for (my $i = 0; $i <= $#vals; $i++) {
            push(@{$test_plans{$test_params[$i]}}, $vals[$i]);
        }
        $$num_test_plans++;
    }
    close TEST_PLAN;
    
    return \%test_plans;
}

sub run_tests {
    my ($num_test_plans, $test_plans, $test_config, $num_tests, 
        $root, $data_dir_prefix, $ba_test_cfg, $ba_report_level) = @_;

    for (my $t = 0; $t < $num_test_plans; $t++) {
        map {$test_config{$_} = @{$test_plans->{$_}}[$t]} keys %$test_plans;
        my $plan_dir = $root."/".$data_dir_prefix.$t;

        if (!-e $plan_dir) {
            make_path($plan_dir) or die "Error: failed to create $plan_dir: $!\n";
        } elsif (!-d $plan_dir) {
            die "Error: $plan_dir exists and is not a directory\n";
        }

        # create a test configuration file
        my $test_cfg_file = "$plan_dir/$ba_test_cfg";

        open(CONFIG, ">$test_cfg_file") 
            or die "Error: open $test_cfg_file failed: $!\n"; 
        foreach (sort keys %test_config) {
            print CONFIG "$_=$test_config{$_}\n";
        }
        close CONFIG;

        # For each test
        for (my $i = 0; $i < $num_tests; $i++) {
            # create a test directory
            my $test_dir = "$plan_dir/$i";
            if (!-e $test_dir) {
                make_path($test_dir) or die "Error: failed to create $test_dir: $!\n";
            } elsif (!-d $test_dir) {
                die "Error: $test_dir exists and is not a directory\n";
            }
            
            # create a set of test data
            my @make_data = ($make_data, 
                             '-f', "$test_cfg_file",
                             '--data-dir', "$test_dir");
            system(@make_data) == 0 or die "@make_data failed: $!";

            my @camera_files = ();
            my $num_cameras = $test_config{"number-of-cameras"};
            foreach (0 .. $num_cameras-1) {
                push(@camera_files, "$camera_prefix$_.$camera_ext");
            }

            # For each bundle adjustment type
            foreach my $ba_type (@ba_types) {
                my $results_dir = "$test_dir/$ba_type";
                if (!-e $results_dir) {
                    make_path($results_dir) or die "Error: failed to create $results_dir: $!\n";
                } elsif (!-d $results_dir) {
                    die "Error: $results_dir exists and is not a directory\n";
                }

                # run bundle adjustment
                my @ba_test_opts = ('-s',
                    '-R',$results_dir,
                    '-D',$test_dir,
                    '-r',$ba_report_level,
                    '-b',$ba_type,
                    '-f',$test_cfg_file);
                my @ba_test = ($ba_test, @ba_test_opts, @camera_files);
                system(@ba_test) == 0 or die "@ba_test failed: $!";
            }
        }
    }
}

sub read_results {
    my ($num_test_plans, $root, $data_dir_prefix, $num_tests, @data_files) = @_;
    my ($wp_true_file, $wp_init_file, $wp_final_file, 
        $cam_true_file, $cam_init_file, $cam_final_file) = @data_files;

    my @results = ();
    for (my $t = 0; $t < $num_test_plans; $t++) {
        my $plan_dir = $root."/".$data_dir_prefix.$t;
        push @results, {};
        foreach my $ba_type (@ba_types) {
            my @wp_mse = ();
            my @xyz_mse = ();
            my @euler_mse = ();

            for (my $i = 0; $i < $num_tests; $i++) {
                my $test_dir = "$plan_dir/$i";
                my $results_dir = "$test_dir/$ba_type";
                my $wp_true  = read_wp_results("$test_dir/$wp_true_file");
                my $wp_init  = read_wp_results("$results_dir/$wp_init_file");
                my $wp_final = read_wp_results("$results_dir/$wp_final_file");
                my ($xyz_true, $euler_true)   = read_cam_results("$test_dir/$cam_true_file");
                my ($xyz_init, $euler_init)   = read_cam_results("$results_dir/$cam_init_file");
                my ($xyz_final, $euler_final) = read_cam_results("$results_dir/$cam_final_file");
                push @wp_mse, mse($wp_final, $wp_true);
                push @xyz_mse, mse($xyz_final, $xyz_true);
                push @euler_mse, mse($euler_final, $euler_true); 
            }
            $results[$t]{$ba_type} = {wp => \@wp_mse, 
                                      xyz => \@xyz_mse, 
                                      euler => \@euler_mse}; 
        }
    }
    return \@results;
}

sub print_raw_results {
    my ($results, $num_tests, $root) = @_;
    my $num_plans = scalar @$results;

    my @headers = ();
    my @ba_types = keys %{$results->[0]};
    my @data_types = keys %{$results->[0]{$ba_types[0]}};
    foreach my $ba_type (@ba_types) {
        foreach my $data_type (@data_types) {
            push (@headers, $ba_type."_".$data_type);
        }
    }

    for (my $plan = 0; $plan < $num_plans; $plan++) {
        open OUT, ">$root/plan${plan}_raw.txt" 
            or die "Error: Could not open raw results file: $!\n";
        print OUT join("\t",@headers),"\n";
        my @values = ();
        for (my $test = 0; $test < $num_tests; $test++) {
            foreach my $ba_type (@ba_types) {
                foreach my $data_type (@data_types) {
                    my $val = $results->[$plan]{$ba_type}{$data_type}[$test];
                    push(@values, $val);
                }
            }
            print OUT join("\t",@values),"\n";
            @values = ();
        }
        close OUT;
    }
}


sub print_result_stats {
    my ($results,$root) = @_;
    my $num_test_plans = scalar @$results;
    my $stat = Statistics::Descriptive::Full->new();

    open(RESULTS, ">$root/results.txt") or die "Could not open results file: $!\n";

    my @headers = ('test_plan');
    my @ba_types = keys %{$results->[0]};
    my @data_types = qw(wp xyz euler);
    my @stats = ("mean", "stddev", 
                 $percentile_low."pct",
                 $percentile_high."pct");
    foreach my $ba_type (@ba_types) {
        foreach my $data_type (@data_types) {
            foreach my $stat (@stats) {
                push (@headers, $ba_type."_".$data_type."_".$stat);
            }
        }
    }
    print RESULTS join("\t",@headers), "\n";
    for (my $t = 0; $t < $num_test_plans; $t++) {
        my @values = ($t);
        foreach my $ba_type (@ba_types) {
            foreach my $data_type (@data_types) {
                my @data = @{$results->[$t]{$ba_type}{$data_type}};
                $stat->add_data(@data);
                my $mean = $stat->mean();
                my $sd = $stat->standard_deviation();
                my $pct_low = $stat->percentile($percentile_low);
                my $pct_high = $stat->percentile($percentile_high);
                push (@values, $mean,$sd,$pct_low,$pct_high);
                $stat->clear();
            }
        }
        print RESULTS join("\t",@values),"\n";
    }
}
 

##
## BEGIN EXECUTION
##

my $num_test_plans = 0;
my $test_plans = read_test_plans($ARGV[0], \$num_test_plans);

run_tests($num_test_plans, $test_plans, \%test_config, $num_tests,
          $tests_root, $data_dir_prefix, $ba_test_cfg, $ba_report_level);

## Read results
my $results = read_results($num_test_plans, $tests_root, $data_dir_prefix, $num_tests,
                           $wp_true_file, $wp_init_file, $wp_final_file, 
                           $cam_true_file, $cam_init_file, $cam_final_file);

print_raw_results($results, $num_tests,$tests_root);

## Calculate result statistics
print_result_stats($results, $tests_root);
           
