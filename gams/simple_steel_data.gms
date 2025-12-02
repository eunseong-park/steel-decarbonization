*------------------------------------------------------------------------------
* DECLARE PARAMETERS, SETS, DATA
*------------------------------------------------------------------------------

SETS
    i           "Steel plants"  
                /   i1 * i15  /

    f           "Factors"
                /   iore    "Iron ore (tonnes)"
                    coal    "Coking coal (tonnes)"
                    scrp    "Steel scrap (tonnes)" 
                    elec    "Electricity (MWh)"
                    ngas    "Natural gas (tonnes)" /

    t           "Technology type"
                /   bof     "BF-BOF route"
                    eaf     "Scrap-EAF route"
                    dri     "DRI-EAF route" /

    it(i,t)     "Link between plants and technologies"
                /   (i1 * i5).bof, (i6 * i10).eaf, (i11 * i15).dri /
;

alias(i, ii)

PARAMETERS
    abar(t,f)   "Factor use per ton crude steel production"
                /   bof.iore     1.401
                    bof.coal     0.653
                    bof.scrp     0.252
                    bof.elec     0.033
                    eaf.scrp     1.026
                    eaf.elec     0.523
                    dri.scrp     0.579
                    dri.iore     0.852
                    dri.elec     0.707
                    dri.ngas     7.199 /
    vbar(f)     "Reference factor market prices"
                /   iore     33.0
                    coal     64.0
                    scrp    136.0
                    elec     70.0
                    ngas      4.3 /

    rho(f)      "Price elasticity in factor supply"
                /   iore    1.0
                    coal    2.0
                    scrp    0.5
                    elec    0.0
                    ngas    0.0 /
    kappa(f)    "Carbon emissions coefficient"
                /   iore    0.02
                    coal    2.76
                    scrp    0.01
                    elec    0.29
                    ngas    2.34 /

    epsilon     "Price elasticity of steel demand" / -0.3 /
    tau(i,f)    "Plant-specific additional cost (e.g. transport)"
    ylim(i)     "Plant-specific production capacity"

    dbar        "Reference aggregate demand"
    ybar(i)     "Reference output by plant"
;

* Generate some random data to parametrize the model:
tau(i, f)  = uniform(0, 0.1);
ylim(i)    = uniform(10, 15);
ybar(i)    = ylim(i) - uniform(0, 5);

* Set reference demand:
dbar = sum(i, ybar(i));

* Define policy parameters:
PARAMETER
    chi     "Emissions reduction target" 
;

chi = 0;

execute_unload 'data/generated/steel_data.gdx'