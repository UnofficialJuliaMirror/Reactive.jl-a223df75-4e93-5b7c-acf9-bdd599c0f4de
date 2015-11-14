export every, fps, fpswhen, throttle

"""
    throttle(dt, input, f=(acc,x)->x, init=value(input), reinit=x->x)

Throttle a signal to update at most once every dt seconds. By default, the throttled signal holds the last update in the time window.

This behavior can be changed by the `f`, `init` and `reinit` arguments. The `init` and `f` functions are similar to `init` and `f` in `foldp`. `reinit` is called when a new throttle time window opens to reinitialize the initial value for accumulation, it gets one argument, the previous accumulated value.

For example
    y = throttle(0.2, x, push!, Int[], _->Int[])
will create vectors of updates to the integer signal `x` which occur within 0.2 second time windows.

"""
function throttle{T}(dt, node::Node{T}, f=(acc, x) -> x, init=value(node), reinit=x->x)
    output = Node(init, (node,))
    throttle_connect(dt, output, node, f, init, reinit)
    output
end

# Aggregate a signal producing an update at most once in dt seconds
function throttle_connect(dt, output, input, f, init, reinit)
    let collected = init, timer = Timer(x->x, 0)
        add_action!(input, output) do output, timestep
            collected = f(collected,  value(input))
            close(timer)
            timer = Timer(x -> begin push!(output, collected); collected=reinit(collected) end, dt)
        end
    end
end

"""
    every(dt)

A signal that updates every `dt` seconds to the current timestamp. Consider using `fpswhen` or `fps` before using `every`.
"""
function every(dt)
    n = Node(time(), ())
    every_connect(dt, n)
    n
end

function every_connect(dt, output)
    outputref = WeakRef(output)
    timer = Timer(x -> _push!(outputref, time(), ()->close(timer)), dt, dt)
    finalizer(output, _->close(timer))
    output
end

"""
    fpswhen(switch, rate)

returns a signal which when `switch` signal is true, update `rate` times a second. If `rate` is not possible to attain because of slowness in computing dependent signal values, the signal will self adjust to provide the best possible rate.
"""
function fpswhen(switch, rate)
    n = Node(Float64, 0.0, (switch,))
    fpswhen_connect(rate, switch, n)
    n
end

function setup_next_tick(outputref, switchref, dt, wait_dt)
    weakrefdo(switchref, value, ()->false) && Timer(t -> begin
        weakrefdo(switchref, value, ()->false) &&
            weakrefdo(outputref, x -> push!(x, dt))
    end, wait_dt)
end

function weakrefdo(ref, yes, no=()->nothing)
    ref.value != nothing ? yes(ref.value) : no()
end

function fpswhen_connect(rate, switch, output)
    let prev_time = time(),
        dt = 1.0/rate,
        outputref = WeakRef(output)
        switchref = WeakRef(switch)
        switch_ticks = filter(x->x, false, switch) # only turn-ons


        for inp in [output, switch_ticks]
            add_action!(inp, output) do output, timestep
                start_time = time()
                setup_next_tick(outputref, switchref, time()-prev_time, dt)
                prev_time = start_time
            end
        end

        setup_next_tick(outputref, switchref, dt, dt)
    end
end

"""
    fps(rate)

Same as `fpswhen(Input(true), rate)`
"""
fps(rate) = fpswhen(Node(Bool, true, ()), rate)