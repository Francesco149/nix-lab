function diff-system
  set host $argv[1]
  if test -z "$host"
    echo "Usage: diff-system <machine>"
    return 1
  end
  set machine (nix eval --raw .#deploy.nodes.$host.hostname)
  set new_path (nom build .#nixosConfigurations.$host.config.system.build.toplevel --no-link --print-out-paths 2>&1 | tail -1)
  set current (ssh root@$machine readlink /run/current-system)
  nix copy --no-check-sigs --from ssh-ng://root@$machine $current
  nvd diff $current $new_path
end

function build-system
  set host $argv[1]
  if test -z "$host"
    echo "Usage: build-system <machine>"
    return 1
  end
  nom build .#nixosConfigurations.$host.config.system.build.toplevel
end

function check-inputs
    set metadata (nix flake metadata --json)

    echo "=== Duplicate input check ==="

    set inputs (echo $metadata | jq -r '.locks.nodes | keys[]' | grep -v root)

    set found_dupes 0
    for input in $inputs
        set matches (echo $metadata | jq -r --arg i $input \
            '.locks.nodes | to_entries[] | select(.key == $i or (.key | startswith($i + "_"))) | .key')

        if test (count $matches) -gt 1
            set found_dupes 1
            echo ""
            echo "⚠ $input has multiple versions:"
            for match in $matches
                set hash (echo $metadata | jq -r --arg m $match \
                    '.locks.nodes[$m].locked.narHash // "follows"')
                echo "  - $match: $hash"
            end
        end
    end

    if test $found_dupes -eq 0
        echo "✓ no duplicates found"
    end

    echo ""
    echo "=== All inputs ==="
    echo $metadata | jq -r '.locks.nodes | to_entries[] | select(.key != "root") | 
        "\(.key): \(.value.locked.narHash // "follows \(.value.follows | join("/"))")"'
end