use Data::Dumper;
my $commit_message=@ARGV[0];
my $job_id=@ARGV[1];
my $matrix=@ARGV[2];
my $output_name=@ARGV[3];

my @cmds = ();
my $has_debug = 0;
open my $fh, '<', \$commit_message or die $!;
while (<$fh>) {
    while(/\[(.*?)\s+(.*?)\]/g)
    {
        my @cmd = map {$_ =~ s/^\s+//; [split /\./, $_]} split(/,/, $2);
        push(@cmds, [$1, \@cmd]);
        $has_debug = $has_debug || $1 eq 'debug';
    }
}
close $fh or die $!;

my @matrix_keys = ();
my @matrix_elements = ();
open my $fh, '<', \$matrix or die $!;
while (<$fh>) {
    while(/\s*(.+?):\s*?\[(.*?)\]/g)
    {
        push(@matrix_keys, $1);
        (my $val = $2) =~ s/,//g;
        $val =~ s/^\s+|\[|\]|\s+$//g;
        push(@matrix_elements, [split(' ', $val)]);
    }
}
close $fh or die $!;

my @stack=(0) x @matrix_elements;
my @running = ();
my @debugging = ();

while (@stack[0] <= $#{@matrix_elements[0]}) {
    my @job_path = ($job_id);
    for $level2 (0..$#stack) {
        push(@job_path, @{@matrix_elements[$level2]}[@stack[$level2]]);
    }
    # print join('.', @job_path) . ":\n";

    my $run = !$has_debug;
    my $can_skip = 1;
    my $debug = 0;
    for my $cmd (@cmds) {
        # print("\t" . @$cmd[0] . ":\n");
        for my $arg (@{@$cmd[1]}) {
            my $prev_part = -1;
            my $found;
            # print("\t\t" . join('.', @$arg) . ": ");
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
            # print($found . "\n");
            if ($found && @$cmd[0] eq 'debug' && $#$arg == $#job_path) {
                $debug = 1;
                $run = 0;
            }
            if (!$has_debug)
            {
                if ($found && !$debug && $can_skip && @$cmd[0] eq 'skip') {
                    $run = 0;
                }
                if ($found && !$debug && @$cmd[0] eq 'run') {
                    $run = 1;
                    $can_skip = 0;
                }
            }
        }
    }
    if ($run) {
        push(@running, [@job_path]);
    }
    if ($debug) {
        push(@debugging, [@job_path]);
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

my $include_string = "";
if ($#running == -1 && $#debugging != -1) {
    @running = @debugging;
}
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
print("$output_name = {\"include\":[$include_string]}\n");
print("::set-output name=".$output_name."::{\"include\":[$include_string]}\n");