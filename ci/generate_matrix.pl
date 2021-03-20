=pod
    Used in build.yml to dynamicly generate job matrix based on commit message
    and workflow dispatch arguments
    Args:
        - commit message
            which may contain [skip JOB_PATH]
        - comma separated list of debugging jobs (FULL_JOB_PATH-s)
        - name of job for which matrix generated
        - base matrix for job
    FULL_JOB_PATH:
        Dot separated list of matrix elements.
        Starts with job name
        Should contain single value from each row of base matrix in
        the same order as rows
        For example: test.X64.clang.debug, static.ARM64.gcc
    JOB_PATH:
        Same as FULL_JOB_PATH, but may skip any element from path, but should
        have order as matrix rows
        For example: ARM64, test.debug, X64.debug, X64.clang.debug
=cut

use Data::Dumper;
my $commit_message=@ARGV[0];
my $debugging_jobs=@ARGV[1];
my $job_id=@ARGV[2];
my $matrix=@ARGV[3];

my @cmds = (); # ARRAY(ARRAYS(('skip' | 'run'), ARRAYS(CMD_PATH_ARRAY)))
my @matrix_keys = (); # needed for matrix generation
my @matrix_elements = (); # needed to filter running jobs
my @running = (); # ARRAY(ARRAYS(JOB_PATH_ARRAY)))
my $has_debug = 0;

# Parse matrix
open my $fh, '<', \$matrix or die $!;
while (<$fh>) {
    while(/\s*(\w+?):\s*?\[(.*?)\]/g)
    {
        push(@matrix_keys, $1);
        (my $val = $2) =~ s/,//g;
        $val =~ s/^\s+|\[|\]|\s+$//g;
        push(@matrix_elements, [split(' ', $val)]);
    }
}
close $fh or die $!;

# Parse debugging_jobs
my @debug_cmds = (map {$_ =~ s/\s+//; [split /\./, $_]}
                      split(/\s*,\s*/, $debugging_jobs));
$has_debug = $#debug_cmds != -1;

if ($has_debug) {
    @cmds = ['debug', [@debug_cmds]];
}
else {
    # Get all commands from commit_message
    open my $fh, '<', \$commit_message or die $!;
    while (<$fh>) {
        while(/\[(.*?)\s+(.*?)\]/g)
        {
            my @cmd = map {$_ =~ s/^\s+//; [split /\./, $_]}
                          split(/,/, $2);
            push(@cmds, [$1, \@cmd]);
        }
    }
    close $fh or die $!;
}

my @stack=(0) x @matrix_elements;

# Generate all possible matrix combinations and add it to running if it is
# not rejected by skip and not enabled by run commands or not in debugging_jobs
while (@stack[0] <= $#{@matrix_elements[0]}) {
    my @job_path = ($job_id);
    for $level2 (0..$#stack) {
        push(@job_path, @{@matrix_elements[$level2]}[@stack[$level2]]);
    }

    my $run = !$has_debug;
    my $can_skip = 1;
    for my $cmd (@cmds) {
        for my $arg (@{@$cmd[1]}) {
            my $prev_part = -1;
            my $found;
            for my $arg_part (@$arg) {
                $found = 0;
                for my $i ($prev_part+1 .. $#job_path) {
                    my $path_part = @job_path[$i];
                    if ($arg_part eq $path_part)
                    {
                        $prev_part = $i;
                        $found = 1;
                        last;
                    }
                }
                if (!($found)) {
                    last;
                }
            }
            if (!$has_debug && $found && $can_skip && @$cmd[0] eq 'skip') {
                $run = 0;
            }
            if ($found && (@$cmd[0] eq 'run' || @$cmd[0] eq 'debug')) {
                $run = 1;
                $can_skip = 0;
            }
        }
    }
    if ($run) {
        push(@running, [@job_path]);
    }

    @stack[$#stack]++;
    my $temp_level = $#stack;
    while ((@stack[$temp_level] > $#{@matrix_elements[$temp_level]}) &&
        ($temp_level > 0)) {
        @stack[$temp_level] = 0;
        @stack[$temp_level-1]++;
        $temp_level--;
    }
}

# Generate matrix
my $include_string = "";
for $job_path (0..$#running)
{
    $include_string .= "{";
    for $key (0..$#matrix_keys) {
        $include_string .= "\"" . @matrix_keys[$key] . "\": \"" .
                                  @{@running[$job_path]}[$key + 1] . "\"";
        if ($key != $#matrix_keys || $has_debug) {
            $include_string .= ", ";
        }
    }
    if ($has_debug) {
        $include_string .= "\"debugging\": true";
    }
    $include_string .= "}";
    if ($job_path != $#running) {
        $include_string .= ", ";
    }
}

print("run_$job_id = ".($#running != -1 ? "true" : "false")."\n");
print("::set-output name=run_".$job_id."::".
      ($#running != -1 ? "true" : "false")."\n");
print("${job_id}_matrix = {\"include\":[$include_string]}\n");
print("::set-output name=${job_id}_matrix::{\"include\":[$include_string]}\n");