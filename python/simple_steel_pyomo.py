import pyomo.environ as pyo
from pyomo.mpec import Complementarity
import pandas as pd
import h5py
import os

# Ensure output directory exists
output_dir = "output/python"
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

def decode_str(b):
    """Helper to decode bytes to string if necessary."""
    if isinstance(b, bytes):
        return b.decode('utf-8')
    return b

def load_h5_data(h5_path):
    """Loads data from HDF5 file into a dictionary of DataFrames/Scalars."""
    data = {}

    def _load_df(f, key, cols_to_decode):
        raw = f[key][:]
        df = pd.DataFrame(raw)
        for col in cols_to_decode:
            if col in df.columns:
                df[col] = df[col].apply(decode_str)
        return df

    with h5py.File(h5_path, 'r') as f:
        # Sets
        data['i'] = [decode_str(x) for x in f['sets/i'][:]]
        data['f_set'] = [decode_str(x) for x in f['sets/f'][:]]
        data['t'] = [decode_str(x) for x in f['sets/t'][:]]
        
        # Parameters
        data['it'] = _load_df(f, 'sets/it', ['i', 't'])
        data['abar'] = _load_df(f, 'params/abar', ['t', 'f'])
        data['vbar'] = _load_df(f, 'params/vbar', ['f'])
        data['rho'] = _load_df(f, 'params/rho', ['f'])
        data['kappa'] = _load_df(f, 'params/kappa', ['f'])
        data['tau'] = _load_df(f, 'params/tau', ['i', 'f'])
        data['ylim'] = _load_df(f, 'params/ylim', ['i'])
        data['ybar_ref'] = _load_df(f, 'params/ybar', ['i'])

        # Scalars
        data['dbar'] = float(f['scalars/dbar'][()].item())
        data['epsilon'] = float(f['scalars/epsilon'][()].item())
        data['chi'] = float(f['scalars/chi'][()].item())

    return data

def build_and_solve_calibration(data):
    print("--- Solving Calibration LP ---")
    m = pyo.ConcreteModel(name="Calibration")

    # Sets
    m.I = pyo.Set(initialize=data['i'])
    m.F = pyo.Set(initialize=data['f_set'])
    m.T = pyo.Set(initialize=data['t'])

    # Mappings
    plant_tech = dict(zip(data['it']['i'], data['it']['t']))

    # Parameters
    abar_dict = data['abar'].set_index(['t', 'f'])['value'].to_dict()
    def get_abar(t, f): return abar_dict.get((t, f), 0.0)

    vbar_dict = data['vbar'].set_index('f')['value'].to_dict()
    tau_dict = data['tau'].set_index(['i', 'f'])['value'].to_dict()
    ylim_dict = data['ylim'].set_index('i')['value'].to_dict()
    dbar = data['dbar']

    # Variables
    m.Y = pyo.Var(m.I, domain=pyo.NonNegativeReals)

    # Objective
    def obj_rule(model):
        expr = 0
        for i in model.I:
            t_tech = plant_tech[i]
            for f in model.F:
                use = get_abar(t_tech, f)
                cost = vbar_dict[f] + tau_dict.get((i, f), 0.0)
                expr += use * cost * model.Y[i]
        return expr
    m.Obj = pyo.Objective(rule=obj_rule, sense=pyo.minimize)

    # Constraints
    m.Demand = pyo.Constraint(expr=sum(m.Y[i] for i in m.I) >= dbar)

    def capacity_rule(model, i): return model.Y[i] <= ylim_dict[i]
    m.Capacity = pyo.Constraint(m.I, rule=capacity_rule)

    # Solve
    solvers = ['glpk', 'cbc', 'ipopt']
    solver = None
    for s in solvers:
        try:
            if pyo.SolverFactory(s).available():
                solver = pyo.SolverFactory(s)
                print(f"Using solver: {s}")
                break
        except (ImportError, OSError, ValueError):
            # This specific solver or its executable is not found/available.
            pass    
    if solver is None:
        print("WARNING: No suitable solver found. Calibration may fail.")
        solver = pyo.SolverFactory('ipopt')

    results = solver.solve(m, tee=False)
    
    if (results.solver.status == pyo.SolverStatus.ok) and \
       (results.solver.termination_condition == pyo.TerminationCondition.optimal):
        print("Calibration Optimal.")
    else:
        print(f"Calibration Failed: {results.solver.termination_condition}")

    # Extract Duals
    m.dual = pyo.Suffix(direction=pyo.Suffix.IMPORT)
    solver.solve(m, tee=False)

    pbar = m.dual[m.Demand]
    rbar = {i: abs(m.dual[m.Capacity[i]]) for i in m.I}
    ybar_vals = {i: pyo.value(m.Y[i]) for i in m.I}

    hbar = {}
    for f in m.F:
        hbar[f] = sum(get_abar(plant_tech[i], f) * ybar_vals[i] for i in m.I)

    kappa_dict = data['kappa'].set_index('f')['value'].to_dict()
    ebar = {}
    for f in m.F:
        ebar[f] = sum(get_abar(plant_tech[i], f) * kappa_dict[f] * ybar_vals[i] for i in m.I)
        
    return pbar, rbar, ybar_vals, hbar, ebar

def build_mcp_model(data, pbar, rbar, ybar, hbar, ebar, chi_target, fixed_carbon_price=None):
    m = pyo.ConcreteModel(name="Steel_MCP")

    m.I = pyo.Set(initialize=data['i'])
    m.F = pyo.Set(initialize=data['f_set'])
    
    plant_tech = dict(zip(data['it']['i'], data['it']['t']))
    
    abar_dict = data['abar'].set_index(['t', 'f'])['value'].to_dict()
    def get_abar(t, f): return abar_dict.get((t, f), 0.0)

    vbar_dict = data['vbar'].set_index('f')['value'].to_dict()
    rho_dict = data['rho'].set_index('f')['value'].to_dict()
    kappa_dict = data['kappa'].set_index('f')['value'].to_dict()
    tau_dict = data['tau'].set_index(['i', 'f'])['value'].to_dict()
    ylim_dict = data['ylim'].set_index('i')['value'].to_dict()
    
    dbar = data['dbar']
    epsilon = data['epsilon']

    m.P = pyo.Var(domain=pyo.NonNegativeReals, initialize=pbar)
    m.V = pyo.Var(m.F, domain=pyo.NonNegativeReals, initialize=lambda m, f: vbar_dict[f])
    m.R = pyo.Var(m.I, domain=pyo.NonNegativeReals, initialize=lambda m, i: rbar[i])
    init_w = 0.0 if fixed_carbon_price is None else fixed_carbon_price
    m.W = pyo.Var(domain=pyo.NonNegativeReals, initialize=init_w)
    m.Y = pyo.Var(m.I, domain=pyo.NonNegativeReals, initialize=lambda m, i: ybar[i])

    # 1. Zero Profit
    def zpf_rule(model, i):
        t_tech = plant_tech[i]
        cost_factors = sum(get_abar(t_tech, f) * (model.V[f] + tau_dict.get((i,f), 0)) for f in model.F)
        cost_carbon = sum(model.W * kappa_dict[f] * get_abar(t_tech, f) for f in model.F)
        lhs = cost_factors + model.R[i] + cost_carbon - model.P
        return (lhs >= 0, model.Y[i] >= 0)
    m.zpf = Complementarity(m.I, rule=zpf_rule)

    # 2. Market Clearance Steel
    def mkt_y_rule(model):
        supply = sum(model.Y[i] for i in model.I)
        demand = dbar * (1 + epsilon * (model.P / pbar - 1))
        return (supply - demand >= 0, model.P >= 0)
    m.mkt_y = Complementarity(rule=mkt_y_rule)

    # 3. Market Clearance Factors
    def mkt_f_rule(model, f):
        supply = hbar[f] * (1 + rho_dict[f] * (model.V[f] / vbar_dict[f] - 1))
        demand = sum(get_abar(plant_tech[i], f) * model.Y[i] for i in model.I)
        return (supply - demand >= 0, model.V[f] >= 0)
    m.mkt_f = Complementarity(m.F, rule=mkt_f_rule)

    # 4. Capacity
    def capacity_rule(model, i):
        return (ylim_dict[i] - model.Y[i] >= 0, model.R[i] >= 0)
    m.capacity = Complementarity(m.I, rule=capacity_rule)

    # 5. Carbon Market
    def mkt_co2_rule(model):
        total_emissions = sum(sum(get_abar(plant_tech[i], f) * kappa_dict[f] for f in model.F) * model.Y[i] for i in model.I)
        
        if fixed_carbon_price is not None:
            return Complementarity.Skip
        else:
            if chi_target == 0:
                 return Complementarity.Skip
            else:
                cap = chi_target * sum(ebar[f] for f in model.F)
                return (cap - total_emissions >= 0, model.W >= 0)

    if fixed_carbon_price is None and chi_target > 0:
        m.mkt_co2 = Complementarity(rule=mkt_co2_rule)
    
    if fixed_carbon_price is not None:
        m.W.fix(fixed_carbon_price)
    elif chi_target == 0:
        m.W.fix(0.0)

    return m

def solve_mcp(model):
    solver_name = 'pathampl'
    solver = pyo.SolverFactory(solver_name)
    if not solver.available():
        print(f"ERROR: Solver '{solver_name}' not available.")
        return False
    
    results = solver.solve(model, tee=False)
    
    if (results.solver.status == pyo.SolverStatus.ok) and \
       (results.solver.termination_condition == pyo.TerminationCondition.optimal):
        return True
    else:
        print(f"Solve Status: {results.solver.termination_condition}")
        return False

def collect_results(m, data, scenario_name):
    plant_tech = dict(zip(data['it']['i'], data['it']['t']))
    kappa_dict = data['kappa'].set_index('f')['value'].to_dict()
    abar_dict = data['abar'].set_index(['t', 'f'])['value'].to_dict()
    def get_abar(t, f): return abar_dict.get((t, f), 0.0)

    prod = sum(pyo.value(m.Y[i]) for i in m.I)
    emis = sum(sum(get_abar(plant_tech[i], f) * kappa_dict[f] for f in m.F) * pyo.value(m.Y[i]) for i in m.I)
    
    return {
        "Scenario": scenario_name,
        "Production": prod,
        "Emissions": emis,
        "Steel Price": pyo.value(m.P),
        "Carbon Price": pyo.value(m.W)
    }

def main():
    print("Initializing Pyomo Model...")
    h5_path = "data/generated/steel_data.h5"
    if not os.path.exists(h5_path):
        print(f"Error: Data file {h5_path} not found. Run data generation first.")
        return

    data = load_h5_data(h5_path)
    
    pbar, rbar, ybar, hbar, ebar = build_and_solve_calibration(data)
    print(f"Calibration Pbar: {pbar:.2f}")

    results_list = []

    print("\n--- Reference Scenario ---")
    m_ref = build_mcp_model(data, pbar, rbar, ybar, hbar, ebar, chi_target=0)
    if solve_mcp(m_ref):
        results_list.append(collect_results(m_ref, data, "Reference"))
    else:
        print("Reference failed.")

    print("\n--- Cap & Trade (Chi=0.8) ---")
    m_cap = build_mcp_model(data, pbar, rbar, ybar, hbar, ebar, chi_target=0.8)
    if solve_mcp(m_cap):
        results_list.append(collect_results(m_cap, data, "Cap (-20%)"))
    else:
        print("Cap & Trade failed.")

    print("\n--- Carbon Tax (W=10) ---")
    m_tax = build_mcp_model(data, pbar, rbar, ybar, hbar, ebar, chi_target=0, fixed_carbon_price=10)
    if solve_mcp(m_tax):
        results_list.append(collect_results(m_tax, data, "Tax ($10/tCO2)"))
    else:
        print("Carbon Tax failed.")

    if results_list:
        df = pd.DataFrame(results_list)
        print("\nResults:")
        print(df.round(2))
        out_path = "output/python/simple_steel_results_pyomo.csv"
        df.to_csv(out_path, index=False)
        print(f"Saved to {out_path}")

if __name__ == "__main__":
    main()
