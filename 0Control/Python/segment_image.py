import os
import sys
import subprocess

def check_file(filename):
    # verify the file has the expected data
    import h5py
    f = h5py.File(filename)
    if set(f.keys()) != set(['segs', 'original_coords']):
        os.unlink(f)
        return False
    return True

try:
    args = sys.argv[1:]

    slice_file = args[0]
    prob_file = args[1]
    output_file = args[2]
    coords = "'" + "','".join(args[3:]) + "'"

    if os.path.exists(output_file):
        print output_file, "already exists"
        if check_file(output_file):
            sys.exit(0)

    print "Computing probabilities", jobidx, args

    cubedir = os.path.join(os.environ['CONNECTOME'], 'Pipeline', 'CubeDicing')
    os.environ['MATLABPATH'] = cubedir

    command = "try, segment_image('%s', '%s', '%s', %s), catch err, display(getReport(err, 'extended')), exit(1), end, exit(0)"
    command = command % (slice_file, prob_file, output_file, coords)
    print "Running matlab command:", command
    subprocess.check_call(['matlab', '-nojvm', '-nodesktop', '-nosplash', '-r', command], env=os.environ) 
    assert check_file(output_file), "Bad data in file, exiting!"
except KeyboardInterrupt:
    pass
